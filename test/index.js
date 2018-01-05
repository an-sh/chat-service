'use strict'
/* eslint-env mocha */

const _ = require('lodash')
const config = require('./config')
const testutils = require('./testutils')
// const wtf = require('wtfnode')

before(testutils.checkDB)
after(() => {
  if (testutils.redis) {
    testutils.redis.quit()
  }
  // setTimeout(() => wtf.dump(), 1000)
})

describe('Chat service.', function () {
  _.forEach(
    config.states,
    state => describe(
      `State: '${state.state}', adapter: '${state.adapter}'.`,
      function () {
        before(() => testutils.setState(state))

        describe('Server initialisation', require('./initialization'))

        describe('Client connection', require('./connection'))

        describe('Room management', require('./roomManagement'))

        describe('Room messaging', require('./roomMessaging'))

        describe('Room permissions', require('./roomPermissions'))

        describe('Direct messaging', require('./directMessaging'))

        describe('Direct permissions', require('./directPermissions'))

        describe('Hooks execution', require('./hooks'))

        describe('Server-side API', require('./api'))

        describe('Server-side API permissions', require('./apiPermissions'))

        describe('Parameters validation', require('./validation'))

        describe('Server errors handling', require('./errorsHandling'))

        describe('State consistency recovery', require('./consistencyRecovery'))
      }))

  describe('Service cluster with multiple nodes', require('./serviceCluster'))
})
