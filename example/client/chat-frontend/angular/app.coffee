
require './controllers.coffee'
require './directives.coffee'

angular.module 'chatTemplates', []

chatApp = angular.module 'chatApp',
  [ 'ui.router', 'chatControllers', 'chatDirectives', 'chatTemplates' ]

chatApp.config ($stateProvider, $urlRouterProvider) ->
  $urlRouterProvider.otherwise '/login'
  $stateProvider
  .state 'chat', {
    controller: 'chatController'
    templateUrl: 'partials/chat.html'
    url: '/chat/:room'
  }
  .state 'messages', {
    controller: 'messagesController'
    parent : 'chat'
    templateUrl: 'partials/messages.html'
    url: '/messages'
  }
  .state 'users', {
    controller: 'usersController'
    parent : 'chat'
    templateUrl: 'partials/users.html'
    url: '/users'
  }
  .state 'blacklist', {
    controller: 'blacklistController'
    parent : 'chat'
    templateUrl: 'partials/blacklist.html'
    url: '/blacklist'
  }
  .state 'login', {
    controller: 'loginController'
    templateUrl: 'partials/login.html'
    url: '/login'
  }
