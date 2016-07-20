/* eslint-env mocha */

const _ = require('lodash')
const config = require('./config')
const testutils = require('./testutils')

before(testutils.checkDB)

describe('Chat service.', function () {
  _.forEach(
    config.states,
    state => describe(
      `State: '${state.state}', adapter: '${state.adapter}'.`,
      function () {
        before(() => testutils.setState(state))

        describe('Initialization', require('./initialization'))

        describe('Connection', require('./connection'))

        describe('Room management', require('./roomManagement'))

        describe('Room messaging', require('./roomMessaging'))

        describe('Room permissions', require('./roomPermissions'))

        describe('Direct messaging', require('./directMessaging'))

        describe('Direct permissions', require('./directPermissions'))

        describe('Hooks', require('./hooks'))

        describe('API', require('./api'))

        describe('API permissions', require('./apiPermissions'))

        describe('Validation', require('./validation'))

        describe('Errors handling', require('./errorsHandling'))

        describe('Consistency recovery', require('./consistencyRecovery'))
      }))

  describe('Service cluster', require('./serviceCluster'))
})
