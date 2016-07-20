let redisClusterConnect = [ { port: 30001, host: '127.0.0.1' } ]
let redisConnect = 'localhost:6379'

if (process.env.TEST_REDIS_CLUSTER) {
  var redisConfig = { state: 'redis',     stateOptions: {useCluster: true, redisOptions: [ redisClusterConnect ]},     adapter: 'redis', adpterOptions: redisConnect }
  var states = [ redisConfig ]
} else {
  var memoryConfig = { state: 'memory', adapter: 'memory' }
  var redisConfig = {state: 'redis', stateOptions: { redisOptions: redisConnect},     adapter: 'redis', adpterOptions: redisConnect }
  var states = [ memoryConfig, redisConfig ]
}

export { undefined as cleanupTimeout, undefined as host, memoryConfig, undefined as namespace, undefined as port, redisClusterConnect, redisConfig, redisConnect, undefined as roomName1, undefined as roomName2, states, undefined as user1, undefined as user2, undefined as user3 }
