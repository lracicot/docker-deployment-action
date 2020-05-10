#!/bin/sh
set -eu

execute_ssh(){
  ssh -q -t -i "$HOME/.ssh/id_rsa" \
      -o UserKnownHostsFile=/dev/null \
      -o StrictHostKeyChecking=no "$INPUT_REMOTE_DOCKER_HOST" "$@"
}

if [ -z "$INPUT_REMOTE_DOCKER_HOST" ]; then
    echo "Input remote_docker_host is required!"
    exit 1
fi

if [ -z "$INPUT_SSH_PUBLIC_KEY" ]; then
    echo "Input ssh_public_key is required!"
    exit 1
fi

if [ -z "$INPUT_SSH_PRIVATE_KEY" ]; then
    echo "Input ssh_private_key is required!"
    exit 1
fi

if [ -z "$INPUT_DEPLOY_PATH" ]; then
  INPUT_DEPLOY_PATH=~/docker-deployment
fi

if [ -z "$INPUT_STACK_FILE_NAME" ]; then
  INPUT_STACK_FILE_NAME=docker-compose.yaml
fi

if [ -z "$INPUT_KEEP_FILES" ]; then
  INPUT_KEEP_FILES=4
else
  INPUT_KEEP_FILES=$((INPUT_KEEP_FILES+1))
fi

case $INPUT_DEPLOYMENT_MODE in

  docker-swarm)
    DEPLOYMENT_COMMAND="docker stack deploy --compose-file $INPUT_STACK_FILE_NAME"
  ;;

  *)
    DEPLOYMENT_COMMAND="docker-compose -f $INPUT_STACK_FILE_NAME"
  ;;
esac

SSH_HOST=${INPUT_REMOTE_DOCKER_HOST#*@}

echo "Registering SSH keys..."

# register the private key with the agent.
mkdir -p "$HOME/.ssh"
printf '%s' "$INPUT_SSH_PRIVATE_KEY" > "$HOME/.ssh/id_rsa"
chmod 600 "$HOME/.ssh/id_rsa"
eval $(ssh-agent)
ssh-add "$HOME/.ssh/id_rsa"

printf '%s %s\n' "$SSH_HOST" "$INPUT_SSH_PUBLIC_KEY" >> /etc/ssh/ssh_known_hosts

if ! [ -z "$INPUT_COPY_STACK_FILE" ] && [ $INPUT_COPY_STACK_FILE = 'true' ] ; then
  execute_ssh mkdir -p "$INPUT_DEPLOY_PATH/stacks"
  FILE_NAME="docker-stack-$(date +%Y%m%d%s).yaml"
  scp $INPUT_STACK_FILE_NAME "$INPUT_REMOTE_DOCKER_HOST:$INPUT_DEPLOY_PATH/$FILE_NAME"
  execute_ssh ln -nfs "$INPUT_DEPLOY_PATH/$FILE_NAME" "$INPUT_DEPLOY_PATH/$INPUT_STACK_FILE_NAME"
  execute_ssh ls -t docker-stack-* 2>/dev/null |  tail -n +$INPUT_KEEP_FILES | xargs rm --  2>/dev/null
  execute_ssh ${DEPLOYMENT_COMMAND} "$@" 2>&1
else
  echo "Connecting to $INPUT_REMOTE_DOCKER_HOST..."
  ${DEPLOYMENT_COMMAND} --log-level debug --host "ssh://$INPUT_REMOTE_DOCKER_HOST" "$@" 2>&1
fi