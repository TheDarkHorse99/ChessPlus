# Running sims from a cloud chat (no PC needed)

Set up Oct 2026 so Mac can start Plusfish runs from his phone while the PC is
off. A cloud Claude Code session talks to AWS with its own access key and runs
commands on the sims server through AWS Systems Manager ("Run Command"), so it
needs no SSH key and no change to the server's firewall.

## The same key on Mac's PC (26 Oct 2026)

The browser sign-in (`aws login`) lapses every day, so `tools/sims_server.sh` now
uses the profile `chessplus-sims`: the `claude-sims` user's access key stored
with `aws configure --profile chessplus-sims` (region us-east-2) on the PC, never
in the repo or in chat. The policy gained two statements for this: opening the
sims server's security group to a new home address
(`ec2:AuthorizeSecurityGroupIngress`, `ec2:DescribeSecurityGroups`) and read-only
Cost Explorer (`ce:GetCostAndUsage`, `ce:GetCostForecast`). Until the profile
exists the script falls back to the `chessplus` browser login.

## What Mac sets up once (AWS website, works on a phone)

1. **Let the server take commands through AWS.** EC2 > Instances >
   `chessplus-sims` > Actions > Security > Modify IAM role > Create new IAM
   role: trusted entity "AWS service", use case "EC2", permission
   `AmazonSSMManagedInstanceCore`, name `chessplus-sims-ssm`. Back on Modify IAM
   role, pick `chessplus-sims-ssm` and press Update IAM role. (Ubuntu's server
   images already include the agent that listens for these commands.)
2. **A key for Claude that can only touch the sims server.** IAM > Policies >
   Create policy > JSON: paste `tools/sims_server/remote-policy.json`, name it
   `chessplus-sims-remote`. IAM > Users > Create user `claude-sims` (no console
   access) > Attach policies directly > `chessplus-sims-remote`. Then open the
   user > Security credentials > Create access key > "Application running
   outside AWS". AWS shows the secret once.
3. **Give it to the cloud environment, not the chat.** In the Claude app, the
   cloud environment menu in a session's title bar > Edit: add
   `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_DEFAULT_REGION` =
   `us-east-2` (under Network secrets if offered, else environment variables).
   Only new sessions see them. Never paste the key into a chat.
4. **The AWS tool in the cloud.** The session installs the AWS CLI with
   `pip install awscli` (from PyPI, Apache 2.0: awscli ~20 MB + botocore
   ~16 MB + small helpers). Ask Mac before the first download, as for any
   download; once he's OK'd it, the environment's setup script can do it.

What the key can do: start, stop and look at the sims server, and run commands
on it. Nothing else in the project (no other servers, no billing, no IAM). To
cut it off: IAM > Users > `claude-sims` > Security credentials > deactivate or
delete the key. Costs: Systems Manager Run Command is free; the server is the
usual ~$2.54/hour while running.

## How a cloud session runs a job

Region `us-east-2`. Find the server's ID by its name first (the key may look up
any server, but only start, stop and command this one):

    ID=$(aws ec2 describe-instances --filters Name=tag:Name,Values=chessplus-sims \
      --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' --output text)

(`remote-policy.json` says `INSTANCE_ID` where the real policy in AWS names it.)

1. `aws ec2 start-instances --instance-ids $ID`, then wait
   (`aws ec2 wait instance-running ...`) and until
   `aws ssm describe-instance-information` lists it as Online (about a minute
   after boot).
2. Send commands with `aws ssm send-command --document-name AWS-RunShellScript
   --instance-ids $ID --parameters 'commands=[...]'` and read
   them back with `aws ssm get-command-invocation`. Commands run as root: run
   the work as the `ubuntu` user (`sudo -iu ubuntu bash -lc '...'`), where Rust,
   `~/ChessPlus` and `~/plusfish-work/` live. Set a long
   `--timeout-seconds` / `executionTimeout` only for short commands; start long
   jobs with `nohup ... &` (as in CLAUDE.md's run recipe) so the command returns
   at once, then check on them with later commands.
3. Update and rebuild first, as in CLAUDE.md (`git fetch --depth 1 origin main
   && git reset --hard origin/main && cd engine/plusfish && cargo build
   --release`), and note the commit.
4. A command's printed output comes back cut at 24,000 characters, so fetch
   reports in pieces (`sed -n '1,300p' file`, then the next lines, or
   `gzip -c file | base64` split into chunks and joined here). File them in
   `balance/results/run<N>/` with a README, as usual.
5. Finish every run with `aws ec2 stop-instances --instance-ids
   $ID`, a stop through AWS, never a `shutdown` on the server:
   AWS's cost tracker kept billing servers that switched themselves off from
   inside for hours afterwards (Oct 2026). The server's own switch-off 20
   minutes after the last Plusfish job (the idle timer) is only the backup.
