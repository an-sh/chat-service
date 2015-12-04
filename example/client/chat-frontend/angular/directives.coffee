
chatDirectives = angular.module 'chatDirectives', []

chatDirectives.directive 'ngEnter', ->
  (scope, element, attrs) ->
    element.bind 'keydown keypress', (event) ->
      if event.which == 13
        scope.$apply -> scope.$eval attrs.ngEnter
        event.preventDefault()

chatDirectives.directive 'scrollInfo', ->
  (scope, element, attrs) ->
    element.bind 'scroll', ->
      e = element[0]
      scope.$apply ->
        fn = scope.$eval attrs.scrollInfo
        fn(e.offsetHeight + e.scrollTop, e.scrollHeight)
