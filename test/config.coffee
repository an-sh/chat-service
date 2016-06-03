
redisClusterConnect = [ { port : 30001, host : '127.0.0.1' } ]
redisConnect = ''

memoryConfig = { state : 'memory', adapter : 'memory' }

redisConfig = { state : 'redis', stateOptions : { redisOptions : redisConnect }
  , adapter : 'redis', adpterOptions : redisConnect }

redisClusterConfig = { state : 'redis'
  , stateOptions : { useCluster : true, redisOptions : [ redisClusterConnect ] }
  , adapter : 'redis', adpterOptions : redisConnect }

if process.env.TEST_REDIS_CLUSTER == 'true'
  states = [ redisClusterConfig ]
else
  states = [ memoryConfig, redisConfig ]


module.exports= {
  memoryConfig
  port : 8000
  redisClusterConfig
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
