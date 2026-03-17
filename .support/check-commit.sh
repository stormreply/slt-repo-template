#/bin/bash

docker run \
    --entrypoint /bin/bash \
    -e "USERID=$(id -u):$(id -g)" \
    -e "TOKEN=$TOKEN" \
    -v $(pwd):/lint \
    -w /lint \
    ghcr.io/antonbabenko/pre-commit-terraform:latest -c '
    git config --global url."https://x-access-token:$TOKEN@github.com/".insteadOf "https://github.com/"
    # git config --list --show-origin
    terraform --version
    pre-commit run -a
    '
