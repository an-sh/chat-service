
require('coffee-script/register');
var app = require('./build/app.coffee');
var port = process.env.PORT || 3000;

function start() {
  var server = app.listen(port, function() {
    console.log('Express server listening on port ' + server.address().port);
  });
}

module.exports = start;
