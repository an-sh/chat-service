
states = [
  { state : 'memory', adapter : 'memory' }
  { state : 'redis', adapter : 'redis' }
]

module.exports=
  port : 8000
  user1 : 'userName1'
  user2 : 'userName2'
  user3 : 'userName3'
  roomName1 : 'room1'
  roomName2 : 'room2'
  redisConnect : ''
  states : states
