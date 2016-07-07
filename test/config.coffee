
redisClusterConnect = [ { port : 30001, host : '127.0.0.1' } ]
redisConnect = 'localhost:6379'


if process.env.TEST_REDIS_CLUSTER
  redisConfig = { state : 'redis'
    , stateOptions : {useCluster : true, redisOptions : [ redisClusterConnect ]}
    , adapter : 'redis', adpterOptions : redisConnect }
  states = [ redisConfig ]
else
  memoryConfig = { state : 'memory', adapter : 'memory' }
  redisConfig = {state : 'redis', stateOptions : { redisOptions : redisConnect}
    , adapter : 'redis', adpterOptions : redisConnect }
  states = [ memoryConfig, redisConfig ]


module.exports= {
  cleanupTimeout : 4000
  host : 'ws://localhost'
  memoryConfig
  namespace : '/chat-service'
  port : 8000
  redisClusterConnect
  redisConfig
  redisConnect
  roomName1 : 'room1'
  roomName2 : 'room2'
  states
  user1 : 'userName1'
  user2 : 'userName2'
  user3 : 'userName3'
}
