
redisClusterConnect = [ { port : 30001, host : '127.0.0.1' } ]

if process.env.TEST_REDIS_CLUSTER == 'true'
  states = [ { state : 'redis'
    , stateOptions : { useCluster : true
      , redisOptions : [ redisClusterConnect ] }
    , adapter : 'redis' } ]
else
  states = [
    { state : 'memory', adapter : 'memory' }
    { state : 'redis', adapter : 'redis' }
  ]


module.exports=
  port : 8000
  redisClusterConnect : redisClusterConnect
  redisConnect : ''
  roomName1 : 'room1'
  roomName2 : 'room2'
  states : states
  user1 : 'userName1'
  user2 : 'userName2'
  user3 : 'userName3'
