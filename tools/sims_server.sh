#!/usr/bin/env bash
# The Overchess sims server on AWS (Mac's project, us-east-2): a c8g.16xlarge
# (64 Graviton4 cores, Arm) named "chessplus-sims", kept stopped between runs
# (Mac's choice).
# Every run ends with "stop" from here, a stop through AWS (Mac, Oct 2026):
# AWS's cost tracker kept billing two servers that had switched themselves off
# from inside (no AWS call) for hours afterwards. So jobs don't end with a
# shutdown of their own: "wait" waits for the job's end marker, then copy the
# results and "stop". The server's own idle switch-off (20 minutes without a
# Plusfish job, the timer in tools/sims_server/) is only the backup.
# Its address changes every time it starts, so "start" looks it up and points
# the SSH shortcut "chessplus-sims" (in ~/.ssh/config) at it.
#
#   bash tools/sims_server.sh status         running / stopped, and its address
#   bash tools/sims_server.sh start          start it, wait until it takes SSH
#   bash tools/sims_server.sh wait <file>    wait until <file> exists on it (a
#                                            job's end marker); fails if the job
#                                            ended without it or the server went away
#   bash tools/sims_server.sh stop           stop it through AWS (it keeps its disk)
#   bash tools/sims_server.sh ssh <command>  run a command on it
#
# Uses the AWS CLI profile "chessplus-sims" (Mac, 26 Oct 2026): a permanent
# access key of the IAM user claude-sims that can only start, stop and
# describe the sims server, open its firewall to a new address, run commands
# on it and read Cost Explorer (policy: tools/sims_server/remote-policy.json),
# so no browser sign-in is needed. SIMS_PROFILE=chessplus falls back to the
# browser login. Also needs the key ~/.ssh/chessplus-key.pem.
set -euo pipefail

PROFILE="${SIMS_PROFILE:-chessplus-sims}"
# Until that profile exists on this PC, the browser login is used.
if ! grep -q "^\[profile $PROFILE\]" ~/.aws/config 2>/dev/null && ! grep -q "^\[$PROFILE\]" ~/.aws/credentials 2>/dev/null; then
	PROFILE=chessplus
fi
NAME=chessplus-sims
# In ~/.ssh/config the key path must have no spaces (the Windows user folder has one), so ~ is used.
KEY="~/.ssh/chessplus-key.pem"
GROUP_NAME=chessplus-sims
AWS_EXE="${AWS_EXE:-$(cygpath -u "$LOCALAPPDATA")/Programs/Amazon/AWSCLIV2/aws.exe}"
# MSYS_NO_PATHCONV: stop Git Bash turning AWS arguments that start with / into
# Windows paths.
export PYTHONIOENCODING=utf-8 MSYS_NO_PATHCONV=1

aws() { "$AWS_EXE" --profile "$PROFILE" --region us-east-2 "$@" | tr -d '\r'; }

instance_id() {
	aws ec2 describe-instances --filters "Name=tag:Name,Values=$NAME" \
		"Name=instance-state-name,Values=pending,running,stopping,stopped" \
		--query "Reservations[0].Instances[0].InstanceId" --output text
}

state_and_address() {
	aws ec2 describe-instances --instance-ids "$1" \
		--query "Reservations[0].Instances[0].[State.Name,PublicDnsName]" --output text
}

# Let this PC's current internet address in over SSH (home addresses change now
# and then). Old addresses are left; they only ever allow SSH with the key.
allow_my_ip() {
	local ip group
	ip="$(curl -fsS https://checkip.amazonaws.com | tr -d '\r\n ')"
	group="$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$GROUP_NAME" --query "SecurityGroups[0].GroupId" --output text)"
	if ! aws ec2 describe-security-groups --group-ids "$group" \
		--query "SecurityGroups[0].IpPermissions[].IpRanges[].CidrIp" --output text | tr '\t' '\n' | grep -qx "$ip/32"; then
		aws ec2 authorize-security-group-ingress --group-id "$group" \
			--ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$ip/32,Description=Mac}]" >/dev/null
		echo "Allowed SSH from this PC's new address $ip."
	fi
}

# Point the "chessplus-sims" SSH shortcut at the server's current address.
write_ssh_config() {
	local host="$1" config="$HOME/.ssh/config"
	touch "$config"
	sed -i '/^# BEGIN chessplus-sims/,/^# END chessplus-sims/d' "$config"
	cat >> "$config" <<EOF
# BEGIN chessplus-sims (written by tools/sims_server.sh)
Host chessplus-sims
  HostName $host
  User ubuntu
  IdentityFile $KEY
  HostKeyAlias chessplus-sims
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30
# END chessplus-sims
EOF
}

id="$(instance_id)"
if [ -z "$id" ] || [ "$id" = "None" ]; then
	echo "No $NAME server found in us-east-2." >&2
	exit 1
fi

case "${1:-status}" in
	status)
		echo "$id $(state_and_address "$id")"
		;;
	start)
		allow_my_ip
		aws ec2 start-instances --instance-ids "$id" >/dev/null
		aws ec2 wait instance-running --instance-ids "$id"
		read -r state host <<< "$(state_and_address "$id")"
		write_ssh_config "$host"
		for _ in $(seq 1 30); do
			if ssh -o BatchMode=yes -o ConnectTimeout=10 chessplus-sims true 2>/dev/null; then
				echo "$NAME is running at $host (ssh chessplus-sims)."
				exit 0
			fi
			sleep 5
		done
		echo "$NAME is running at $host but doesn't answer SSH yet." >&2
		exit 1
		;;
	wait)
		marker="${2:?usage: bash tools/sims_server.sh wait <file on the server>}"
		# Checked every 30 seconds. No marker and no Plusfish job twice in a row
		# means the job ended without finishing; 10 failed connections in a row
		# means the server went away (stopped by its idle check, say).
		quiet=0
		lost=0
		while true; do
			if answer="$(ssh -o BatchMode=yes -o ConnectTimeout=20 chessplus-sims \
				"if [ -e $marker ]; then echo done; elif pgrep -x plusfish >/dev/null || pgrep -x cargo >/dev/null; then echo working; else echo idle; fi" 2>/dev/null)"; then
				lost=0
				case "$answer" in
					done) echo "$marker is there."; exit 0 ;;
					working) quiet=0 ;;
					*) quiet=$((quiet + 1)) ;;
				esac
				if [ "$quiet" -ge 2 ]; then
					echo "No Plusfish job is running and $marker isn't there: the job ended without finishing." >&2
					exit 1
				fi
			else
				lost=$((lost + 1))
				if [ "$lost" -ge 10 ]; then
					echo "Can't reach $NAME any more ($(state_and_address "$id"))." >&2
					exit 1
				fi
			fi
			sleep 30
		done
		;;
	stop)
		aws ec2 stop-instances --instance-ids "$id" >/dev/null
		aws ec2 wait instance-stopped --instance-ids "$id"
		echo "$NAME is stopped."
		;;
	ssh)
		shift
		ssh -o BatchMode=yes chessplus-sims "$@"
		;;
	*)
		echo "Usage: bash tools/sims_server.sh status|start|wait <file>|stop|ssh <command>" >&2
		exit 2
		;;
esac
