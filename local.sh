function build {
  docker build . -t node
}

function run {
  docker run -p 80:80 -d node
}

case $1 in 
  build)
    build
    ;;
  run)
    run
    ;;
  *)
    echo "Command not found."
    ;;
esac