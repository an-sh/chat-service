'use strict'

const Buffer = require('safe-buffer').Buffer
const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const Redis = require('ioredis')
const Room = require('./Room')
const User = require('./User')
const _ = require('lodash')
const promiseRetry = require('promise-retry')
const uid = require('uid-safe')
const { mixin } = require('./utils')

Redis.Promise = require('bluebird')

const namespace = 'chatservice'

function initSet (redis, set, values) {
  return redis.del(set)
    .then(() => values ? redis.sadd(set, values) : null)
}

// State init/remove operations.
class StateOperations {
  constructor (name, exitsErrorName, redis, makeKeyName, stateReset) {
    this.name = name
    this.exitsErrorName = exitsErrorName
    this.redis = redis
    this.makeKeyName = makeKeyName
    this.stateReset = stateReset
  }

  initState (state) {
    return this.redis.setnx(this.makeKeyName('exists'), true).then(isnew => {
      if (!isnew) {
        const error = new ChatServiceError(this.exitsErrorName, this.name)
        return Promise.reject(error)
      }
    }).then(() => this.stateReset(state))
      .then(() => this.redis.setnx(this.makeKeyName('isInit'), true))
  }

  removeState () {
    return this.stateReset().then(() => {
      return this.redis.del(
        this.makeKeyName('exists'), this.makeKeyName('isInit'))
    })
  }

  startRemoving () {
    return this.redis.del(this.makeKeyName('isInit'))
  }
}

// Redis lock operations.
class LockOperations {
  constructor (redis) {
    this.redis = redis
  }

  lock (key, val, ttl) {
    return promiseRetry(
      { minTimeout: 100, retries: 10, factor: 1.5, randomize: true },
      (retry, n) => {
        return this.redis.set(key, val, 'NX', 'PX', ttl).then(res => {
          if (!res) {
            const error = new ChatServiceError('timeout')
            retry(error)
          }
        }).catch(retry)
      })
  }

  unlock (key, val) {
    return this.redis.unlock(key, val)
  }
}

// Redis scripts.
const luaCommands = {
  unlock: {
    numberOfKeys: 1,
    lua: `
if redis.call("get",KEYS[1]) == ARGV[1] then
  return redis.call("del",KEYS[1])
else
  return 0
end`
  },

  messageAdd: {
    numberOfKeys: 5,
    lua: `
local msg = ARGV[1]
local ts = ARGV[2]

local lastMessageId = KEYS[1]
local historyMaxSize = KEYS[2]
local messagesIds = KEYS[3]
local messagesTimestamps = KEYS[4]
local messagesHistory = KEYS[5]

local id = tonumber(redis.call('INCR', lastMessageId))
local maxsz = tonumber(redis.call('GET', historyMaxSize))

redis.call('LPUSH', messagesIds, id)
redis.call('LPUSH', messagesTimestamps, ts)
redis.call('LPUSH', messagesHistory, msg)

local sz = tonumber(redis.call('LLEN', messagesHistory))

if sz > maxsz then
  redis.call('RPOP', messagesIds)
  redis.call('RPOP', messagesTimestamps)
  redis.call('RPOP', messagesHistory)
end

return {id}`
  },

  messagesGet: {
    numberOfKeys: 5,
    lua: `
local id = ARGV[1]
local maxlen = ARGV[2]

local lastMessageId = KEYS[1]
local historyMaxSize = KEYS[2]
local messagesIds = KEYS[3]
local messagesTimestamps = KEYS[4]
local messagesHistory = KEYS[5]

local lastid = tonumber(redis.call('GET', lastMessageId))
local maxsz = tonumber(redis.call('GET', historyMaxSize))
local id = math.min(id, lastid)
local endp = lastid - id
local len = math.min(maxlen, endp)
local start = math.max(0, endp - len)

if start >= endp then
  return {}
end

endp = endp - 1
local msgs = redis.call('LRANGE', messagesHistory, start, endp)
local tss = redis.call('LRANGE', messagesTimestamps, start, endp)
local ids = redis.call('LRANGE', messagesIds, start, endp)

return {msgs, tss, ids}`
  },

  getSocketsToRooms: {
    numberOfKeys: 1,
    lua: `
local result = {}
local sockets = KEYS[1]
local prefix = ARGV[1]
local ids = redis.call('HKEYS', sockets)

if table.getn(ids) == 0 then
  local jsonResult = cjson.encode(cjson.null)
  return {jsonResult}
end

for i, id in pairs(ids) do
  local joined = redis.call('SMEMBERS', prefix .. id)
  result[id] = joined
end

local jsonResult = cjson.encode(result)
return {jsonResult}`
  },

  removeAllSocketsFromRoom: {
    numberOfKeys: 1,
    lua: `
local room = KEYS[1]
local prefix = ARGV[1]
local roomName = ARGV[2]
local ids = redis.call('SMEMBERS', room)

if table.getn(ids) == 0 then
  local jsonResult = cjson.encode(cjson.null)
  return {jsonResult}
end

redis.call('DEL', room)

for i, id in pairs(ids) do
  redis.call('SREM', prefix .. id, roomName)
end

local jsonResult = cjson.encode(ids)
return {jsonResult}`
  },

  removeSocket: {
    numberOfKeys: 2,
    lua: `
local id = KEYS[1]
local sockets = KEYS[2]
local prefix = ARGV[1]
local socketid = ARGV[2]

local rooms = redis.call('SMEMBERS', id)
redis.call('DEL', id)

redis.call('HDEL', sockets, socketid)
local nconnected = redis.call('HLEN', sockets)

local removedRooms = {}
local joinedSockets = {}

for i, room in pairs(rooms) do
  local ismember = redis.call('SISMEMBER', prefix .. room, socketid)
  if ismember == 1 then
    redis.call('SREM', prefix .. room, socketid)
    local njoined = redis.call('SCARD', prefix .. room)
    table.insert(removedRooms, room)
    table.insert(joinedSockets, njoined)
  end
end

if table.getn(removedRooms) == 0 or table.getn(rooms) == 0 then
  local jsonResult = cjson.encode({cjson.null, cjson.null, nconnected})
  return {jsonResult}
end

local jsonResult = cjson.encode({removedRooms, joinedSockets, nconnected})
return {jsonResult}`
  }

}

// Implements state API lists management.
class ListsStateRedis {
  makeKeyName (keyName) {
    return `${namespace}:${this.prefix}:{${this.name}}:${keyName}`
  }

  checkList (listName, num, limit) {
    if (!this.hasList(listName)) {
      const error = new ChatServiceError('noList', listName)
      return Promise.reject(error)
    }
    if (listName === 'userlist') {
      return Promise.resolve()
    }
    return this.redis.scard(listName).then(sz => {
      if (sz + num > limit) {
        const error = new ChatServiceError('listLimitExceeded', listName)
        return Promise.reject(error)
      }
    })
  }

  addToList (listName, elems, limit) {
    const num = elems.length
    return this.checkList(listName, num, limit)
      .then(() => this.redis.sadd(this.makeKeyName(listName), elems))
  }

  removeFromList (listName, elems) {
    return this.checkList(listName)
      .then(() => this.redis.srem(this.makeKeyName(listName), elems))
  }

  getList (listName) {
    return this.checkList(listName)
      .then(() => this.redis.smembers(this.makeKeyName(listName)))
  }

  hasInList (listName, elem) {
    return this.checkList(listName)
      .then(() => this.redis.sismember(this.makeKeyName(listName), elem))
      .then(data => Boolean(data))
  }

  whitelistOnlySet (mode) {
    const whitelistOnly = mode ? true : ''
    return this.redis.set(this.makeKeyName('whitelistMode'), whitelistOnly)
  }

  whitelistOnlyGet () {
    return this.redis.get(this.makeKeyName('whitelistMode'))
      .then(data => Boolean(data))
  }
}

// Implements room state API.
class RoomStateRedis extends ListsStateRedis {
  constructor (server, roomName) {
    super()
    this.server = server
    this.roomName = roomName
    this.name = this.roomName
    this.historyMaxGetMessages = this.server.historyMaxGetMessages
    this.redis = this.server.redis
    this.exitsErrorName = 'roomExists'
    this.prefix = 'rooms'
    mixin(this, StateOperations, this.name, this.exitsErrorName, this.redis,
      this.makeKeyName.bind(this), this.stateReset.bind(this))
  }

  stateReset (state) {
    state = state || {}
    let {
      whitelist, blacklist, adminlist,
      whitelistOnly, owner, historyMaxSize,
      enableAccessListsUpdates = this.server.enableAccessListsUpdates,
      enableUserlistUpdates = this.server.enableUserlistUpdates
    } = state
    if (!owner) { owner = '' }
    return Promise.all([
      initSet(this.redis, this.makeKeyName('whitelist'), whitelist),
      initSet(this.redis, this.makeKeyName('blacklist'), blacklist),
      initSet(this.redis, this.makeKeyName('adminlist'), adminlist),
      initSet(this.redis, this.makeKeyName('userlist'), null),
      this.redis.del(this.makeKeyName('messagesHistory')),
      this.redis.del(this.makeKeyName('messagesTimestamps')),
      this.redis.del(this.makeKeyName('messagesIds')),
      this.redis.del(this.makeKeyName('usersseen')),
      this.redis.set(this.makeKeyName('lastMessageId'), 0),
      this.redis.set(this.makeKeyName('owner'), owner),
      this.whitelistOnlySet(whitelistOnly),
      this.accessListsUpdatesSet(enableAccessListsUpdates),
      this.userlistUpdatesSet(enableUserlistUpdates),
      this.historyMaxSizeSet(historyMaxSize)
    ]).return()
  }

  hasList (listName) {
    return listName === 'adminlist' || listName === 'whitelist' ||
      listName === 'blacklist' || listName === 'userlist'
  }

  ownerGet () {
    return this.redis.get(this.makeKeyName('owner'))
  }

  ownerSet (owner) {
    return this.redis.set(this.makeKeyName('owner'), owner)
  }

  accessListsUpdatesSet (enableAccessListsUpdates) {
    enableAccessListsUpdates = enableAccessListsUpdates ? true : ''
    return this.redis.set(this.makeKeyName('enableAccessListsUpdates'),
      enableAccessListsUpdates)
  }

  accessListsUpdatesGet () {
    return this.redis.get(this.makeKeyName('enableAccessListsUpdates'))
      .then(data => Boolean(data))
  }

  userlistUpdatesSet (enableUserlistUpdates) {
    enableUserlistUpdates = enableUserlistUpdates ? true : ''
    return this.redis.set(this.makeKeyName('enableUserlistUpdates'),
      enableUserlistUpdates)
  }

  userlistUpdatesGet () {
    return this.redis.get(this.makeKeyName('enableUserlistUpdates'))
      .then(data => Boolean(data))
  }

  historyMaxSizeSet (historyMaxSize) {
    let limit = historyMaxSize
    if (!(_.isNumber(historyMaxSize) && historyMaxSize >= 0)) {
      limit = this.server.historyMaxSize
    }
    if (limit === 0) {
      return this.redis.multi()
        .set(this.makeKeyName('historyMaxSize'), limit)
        .del(this.makeKeyName('messagesHistory'))
        .del(this.makeKeyName('messagesTimestamps'))
        .del(this.makeKeyName('messagesIds'))
        .exec()
    } else {
      const last = limit - 1
      return this.redis.multi()
        .set(this.makeKeyName('historyMaxSize'), limit)
        .ltrim(this.makeKeyName('messagesHistory'), 0, last)
        .ltrim(this.makeKeyName('messagesTimestamps'), 0, last)
        .ltrim(this.makeKeyName('messagesIds'), 0, last)
        .exec()
    }
  }

  historyInfo () {
    return this.redis.multi()
      .get(this.makeKeyName('historyMaxSize'))
      .llen(this.makeKeyName('messagesHistory'))
      .get(this.makeKeyName('lastMessageId'))
      .exec()
      .spread(([, historyMaxSize], [, historySize], [, lastMessageId]) => {
        historySize = parseInt(historySize)
        historyMaxSize = parseFloat(historyMaxSize)
        lastMessageId = parseInt(lastMessageId)
        return {
          historySize,
          historyMaxSize,
          historyMaxGetMessages: this.historyMaxGetMessages,
          lastMessageId
        }
      })
  }

  getCommonUsers () {
    return this.redis.sdiff(this.makeKeyName('userlist'),
      this.makeKeyName('whitelist'),
      this.makeKeyName('adminlist'))
  }

  messageAdd (msg) {
    const timestamp = _.now()
    const smsg = JSON.stringify(msg)
    return this.redis.messageAdd(
      this.makeKeyName('lastMessageId'), this.makeKeyName('historyMaxSize'),
      this.makeKeyName('messagesIds'), this.makeKeyName('messagesTimestamps'),
      this.makeKeyName('messagesHistory'), smsg, timestamp)
      .spread(id => {
        msg.id = id
        msg.timestamp = timestamp
        return msg
      })
  }

  convertMessages (msgs, tss, ids) {
    const data = []
    if (!msgs) {
      return Promise.resolve(data)
    }
    for (let idx = 0; idx < msgs.length; idx++) {
      const msg = msgs[idx]
      const obj = JSON.parse(msg, (key, val) => {
        if (val && val.type === 'Buffer') {
          return Buffer.from(val.data)
        } else {
          return val
        }
      })
      obj.timestamp = parseInt(tss[idx])
      obj.id = parseInt(ids[idx])
      data[idx] = obj
    }
    return Promise.resolve(data)
  }

  messagesGetRecent () {
    if (this.historyMaxGetMessages <= 0) { return Promise.resolve([]) }
    const limit = this.historyMaxGetMessages - 1
    return this.redis.multi()
      .lrange(this.makeKeyName('messagesHistory'), 0, limit)
      .lrange(this.makeKeyName('messagesTimestamps'), 0, limit)
      .lrange(this.makeKeyName('messagesIds'), 0, limit)
      .exec()
      .spread(([, msgs], [, tss], [, ids]) => {
        return this.convertMessages(msgs, tss, ids)
      })
  }

  messagesGet (id, maxMessages = this.historyMaxGetMessages) {
    if (maxMessages <= 0) { return Promise.resolve([]) }
    id = _.max([0, id])
    return this.redis.messagesGet(
      this.makeKeyName('lastMessageId'), this.makeKeyName('historyMaxSize'),
      this.makeKeyName('messagesIds'), this.makeKeyName('messagesTimestamps'),
      this.makeKeyName('messagesHistory'), id, maxMessages)
      .spread((msgs, tss, ids) => {
        return this.convertMessages(msgs, tss, ids)
      })
  }

  userSeenGet (userName) {
    return this.redis.multi()
      .hget(this.makeKeyName('usersseen'), userName)
      .sismember(this.makeKeyName('userlist'), userName)
      .exec()
      .spread(([, ts], [, isjoined]) => {
        const joined = Boolean(isjoined)
        const timestamp = ts ? parseInt(ts) : null
        return { joined, timestamp }
      })
  }

  userSeenUpdate (userName) {
    const timestamp = _.now()
    return this.redis.hset(this.makeKeyName('usersseen'), userName, timestamp)
  }
}

// Implements direct messaging state API.
class DirectMessagingStateRedis extends ListsStateRedis {
  constructor (server, userName) {
    super()
    this.server = server
    this.userName = userName
    this.name = this.userName
    this.prefix = 'users'
    this.exitsErrorName = 'userExists'
    this.redis = this.server.redis
    mixin(this, StateOperations, this.name, this.exitsErrorName, this.redis,
      this.makeKeyName.bind(this), this.stateReset.bind(this))
  }

  hasList (listName) {
    return listName === 'whitelist' || listName === 'blacklist'
  }

  stateReset (state) {
    state = state || {}
    let { whitelist, blacklist, whitelistOnly } = state
    whitelistOnly = whitelistOnly ? true : ''
    return Promise.all([
      initSet(this.redis, this.makeKeyName('whitelist'), whitelist),
      initSet(this.redis, this.makeKeyName('blacklist'), blacklist),
      this.redis.set(this.makeKeyName('whitelistMode'), whitelistOnly)
    ]).return()
  }
}

// Implements user state API.
class UserStateRedis {
  constructor (server, userName) {
    this.server = server
    this.userName = userName
    this.name = this.userName
    this.prefix = 'users'
    this.redis = this.server.redis
    mixin(this, LockOperations, this.redis)
  }

  makeKeyName (keyName) {
    return `${namespace}:${this.prefix}:{${this.name}}:${keyName}`
  }

  makeSocketToRooms (id = '') {
    return this.makeKeyName(`socketsToRooms:${id}`)
  }

  makeRoomToSockets (room = '') {
    return this.makeKeyName(`roomsToSockets:${room}`)
  }

  makeRoomLock (room) {
    return this.makeKeyName(`roomLock:${room}`)
  }

  addSocket (id, uid) {
    return this.redis.multi()
      .hset(this.makeKeyName('sockets'), id, uid)
      .hlen(this.makeKeyName('sockets'))
      .exec()
      .spread((_, [, nconnected]) => nconnected)
  }

  getAllSockets () {
    return this.redis.hkeys(this.makeKeyName('sockets'))
  }

  getSocketsToInstance () {
    return this.redis.hgetall(this.makeKeyName('sockets'))
  }

  getRoomToSockets (roomName) {
    return this.redis.smembers(this.makeRoomToSockets(roomName))
  }

  getSocketsToRooms () {
    return this.redis.getSocketsToRooms(
      this.makeKeyName('sockets'), this.makeSocketToRooms())
      .spread(result => {
        const data = JSON.parse(result) || {}
        for (const [k, v] of _.toPairs(data)) {
          if (_.isEmpty(v)) { data[k] = [] }
        }
        return data
      })
  }

  addSocketToRoom (id, roomName) {
    return this.redis.multi()
      .scard(this.makeRoomToSockets(roomName))
      .sadd(this.makeSocketToRooms(id), roomName)
      .sadd(this.makeRoomToSockets(roomName), id)
      .scard(this.makeRoomToSockets(roomName))
      .exec()
      .then(([[, wasjoined], , , [, njoined]]) => {
        const hasChanged = njoined !== wasjoined
        return [njoined, hasChanged]
      })
  }

  removeSocketFromRoom (id, roomName) {
    return this.redis.multi()
      .scard(this.makeRoomToSockets(roomName))
      .srem(this.makeSocketToRooms(id), roomName)
      .srem(this.makeRoomToSockets(roomName), id)
      .scard(this.makeRoomToSockets(roomName))
      .exec()
      .then(([[, wasjoined], , , [, njoined]]) => {
        const hasChanged = njoined !== wasjoined
        return [njoined, hasChanged]
      })
  }

  removeAllSocketsFromRoom (roomName) {
    return this.redis.removeAllSocketsFromRoom(
      this.makeRoomToSockets(roomName), this.makeSocketToRooms(), roomName)
      .spread(result => JSON.parse(result))
  }

  removeSocket (id) {
    return this.redis.removeSocket(
      this.makeSocketToRooms(id), this.makeKeyName('sockets'),
      this.makeRoomToSockets(), id)
      .spread(result => JSON.parse(result))
  }

  lockToRoom (roomName, ttl) {
    return uid(18).then(val => {
      const start = _.now()
      return this.lock(this.makeRoomLock(roomName), val, ttl).then(() => {
        return Promise.resolve().disposer(() => {
          if (start + ttl < _.now()) {
            this.server.emit(
              'lockTimeExceeded', val, { userName: this.userName, roomName })
          }
          return this.unlock(this.makeRoomLock(roomName), val)
        })
      })
    })
  }
}

// Implements global state API.
class RedisState {
  constructor (server, options) {
    this.server = server
    this.options = options
    this.closed = false
    if (this.options.useCluster) {
      this.redis = new Redis.Cluster(...this.options.redisOptions)
    } else {
      const redisOptions = _.castArray(this.options.redisOptions)
      this.redis = new Redis(...redisOptions)
    }
    this.RoomState = RoomStateRedis
    this.UserState = UserStateRedis
    this.DirectMessagingState = DirectMessagingStateRedis
    this.lockTTL = this.options.lockTTL || 10000
    this.instanceUID = this.server.instanceUID
    this.server.redis = this.redis
    for (const [cmd, def] of _.toPairs(luaCommands)) {
      this.redis.defineCommand(cmd, {
        numberOfKeys: def.numberOfKeys,
        lua: def.lua
      })
    }
  }

  makeKeyName (prefix, name, keyName) {
    return `${namespace}:${prefix}:{${name}}:${keyName}`
  }

  hasRoom (name) {
    return this.redis.get(this.makeKeyName('rooms', name, 'isInit'))
  }

  hasUser (name) {
    return this.redis.get(this.makeKeyName('users', name, 'isInit'))
  }

  close () {
    this.closed = true
    return this.redis.quit().return()
  }

  getRoom (name, isPredicate = false) {
    const room = new Room(this.server, name)
    return this.hasRoom(name).then(exists => {
      if (!exists) {
        if (isPredicate) {
          return Promise.resolve(null)
        } else {
          const error = new ChatServiceError('noRoom', name)
          return Promise.reject(error)
        }
      }
      return Promise.resolve(room)
    })
  }

  addRoom (name, state) {
    const room = new Room(this.server, name)
    return room.initState(state).return(room)
  }

  removeRoom (name) {
    return Promise.resolve()
  }

  addSocket (id, userName) {
    return this.redis.hset(
      this.makeKeyName('instances', this.instanceUID, 'sockets'), id, userName)
  }

  removeSocket (id) {
    return this.redis.hdel(
      this.makeKeyName('instances', this.instanceUID, 'sockets'), id)
  }

  getInstanceSockets (uid = this.instanceUID) {
    return this.redis.hgetall(this.makeKeyName('instances', uid, 'sockets'))
  }

  updateHeartbeat () {
    return this.redis.set(
      this.makeKeyName('instances', this.instanceUID, 'heartbeat'), _.now())
      .catchReturn()
  }

  getInstanceHeartbeat (uid = this.instanceUID) {
    return this.redis.get(this.makeKeyName('instances', uid, 'heartbeat'))
      .then(ts => ts ? parseInt(ts) : null)
  }

  getOrAddUser (name, state) {
    const user = new User(this.server, name)
    return this.hasUser(name)
      .then(exists => exists ? null : user.initState(state))
      .catch(ChatServiceError, e => user)
      .return(user)
  }

  getUser (name, isPredicate = false) {
    const user = new User(this.server, name)
    return this.hasUser(name).then(exists => {
      if (!exists) {
        if (isPredicate) {
          return null
        } else {
          const error = new ChatServiceError('noUser', name)
          return Promise.reject(error)
        }
      }
      return Promise.resolve(user)
    })
  }

  addUser (name, state) {
    const user = new User(this.server, name)
    return user.initState(state).return(user)
  }

  removeUser (name) {
    return Promise.resolve()
  }
}

module.exports = RedisState
