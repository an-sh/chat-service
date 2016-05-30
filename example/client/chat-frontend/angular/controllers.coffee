
require './services.coffee'

chatControllers = angular.module 'chatControllers'
  , ['ngStorage', 'chatServices']

getRandomString = (length=16) ->
  chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  return Array length
  .join()
  .split ','
  .map ->
    chars.charAt Math.floor(Math.random() * chars.length)
  .join ''

chatControllers.controller 'messagesController'
  , ($scope, $sessionStorage, $stateParams, $anchorScroll, chatService) ->
    $scope.data.messages = chatService.messages
    room = $stateParams.room
    fn = (error) ->
      unless error
        refresh = (error) ->
          $scope.data.error = error
          if $scope.data.sticky
            chatService.cleanOldMessages room
          $scope.$apply()
          if $scope.data.sticky
            $anchorScroll $scope.data.bottomID
        chatService.bindRefresh refresh
        chatService.roomJoin room, ->
          $scope.functions.send = ->
            if $scope.data.newMessage and $scope.data.newMessage?.length > 0
              chatService.roomMessage room, $scope.data.newMessage
              $scope.data.newMessage = null
              $scope.data.sticky = true
          $scope.functions.checkScroll = (pos, max) ->
            $scope.data.sticky = pos >= max
          $scope.data.sticky = true
          refresh()
    if chatService.isConnected
      fn()
    else
      login = $sessionStorage.login
      chatService.connect login, null
      , { port : CHAT_PORT, namespace : '/chat-service' }
      , fn

chatControllers.controller 'usersController'
  , ($scope, $stateParams, $state, chatService) ->
    room = $stateParams.room
    $scope.functions.ban = (name) ->
      chatService.banUser room, name, ->
        $state.go 'messages', {room : room}
    if room
      $scope.data.userlist = []
      chatService.getUsers room, (error) ->
        if error
          $state.go 'messages', {room : room}
        else
          $scope.data.userlist = chatService.userlists?[room]
          $scope.$apply()

chatControllers.controller 'blacklistController'
  , ($scope, $stateParams, $state, chatService) ->
    room = $stateParams.room
    $scope.functions.unban = (name) ->
      chatService.unBanUser room, name, ->
        $state.go 'messages', {room : room}
    if room
      $scope.data.blacklist = []
      chatService.getBlacklist room, (error) ->
        if error
          $state.go 'messages', {room : room}
        else
          $scope.data.blacklist = chatService.blacklists?[room]
          $scope.$apply()

chatControllers.controller 'chatController'
  , ($scope, $sessionStorage, $stateParams, chatService) ->
    $scope.functions = $scope.functions || {}
    $scope.data = $scope.data || {}
    $scope.data.bottomID = getRandomString()
    $scope.data.login = $sessionStorage.login
    $scope.data.room = $stateParams.room
    $scope.chatService = chatService

chatControllers.controller 'loginController'
  , ($scope, $state, $sessionStorage, chatService) ->
    $scope.data = {}
    $scope.functions = {}
    $scope.functions.connect = (path, opts) ->
      chatService.connect $scope.data.login, null
      , {  port : CHAT_PORT, namespace : '/chat-service' }
      , (error) ->
        if error
          $scope.data.error = error
          $scope.$apply()
        else
          $sessionStorage.login = $scope.data.login
          $scope.data.error = null
          $state.go path, opts
