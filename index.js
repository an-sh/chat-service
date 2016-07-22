var semver = require('semver')

if (semver.lt(process.version, '6.0.0')) {
  module.exports = require('./lib/ChatService')
} else {
  module.exports = require('./src/ChatService')
}
