import httpclient, times, strutils

const targetUrl = "http://localhost:3000/"
const totalRequests = 1000

proc main() =
  var client = newHttpClient()
  let startTime = epochTime()

  for i in 0 ..< totalRequests:
    discard client.get(targetUrl) 

  let endTime = epochTime()
  let duration = endTime - startTime
  echo "Sent ", totalRequests, " requests in ", duration, " seconds"
  echo "RPS: ", (totalRequests.float / duration).formatFloat(ffDecimal, 2), " req/sec"

main()
