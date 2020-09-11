{CompositeDisposable} = require 'atom'

editor = null
extension = null
lines = []

# find the first line at or after start that matches a given regexp
findLine = (regexp, start = 0) ->
  for i in [start...lines.length]
    match = regexp.exec lines[i]
    return {line: i, match: match}  if match?
  throw new Error('no match found')

isCamelCase = (name) ->
  /^[a-z][a-zA-Z0-9]*$/.test name

rules =
  memberFunctionNames: ->
    # only check .h files
    return unless extension is '.h'

    messages = []
    line = -1
    try
      loop
        {line, match} = findLine /^(.*\b(void|ADReal|Real|RealGradient|int|long| & |bool| \* )\s+)([^\(\s]+)\(/, line+1
        if not isCamelCase match[3]
          startPos = match[1].length
          messages.push {type: 'Error', text: 'Member functions should use camelCase', range:[[line,startPos], [line,startPos + match[3].length]]}
    return messages

  virtualDestructors: ->
    return unless extension is '.h'

    messages = []
    line = -1
    try
      loop
        {line, match} = findLine /^(\s*)([^\s]*)(\s*)(~[^\(\s]+)\s*\(/, line+1
        startPos = match[1].length + match[2].length + match[3].length
        if match[2] != 'virtual'
          messages.push {type: 'Error', text: 'All destructors should be virtual', range:[[line,startPos], [line,startPos + match[4].length]]}
    return messages

  prefixIncrement: ->
    return unless extension is '.C'

    messages = []
    line = -1
    try
      loop
        {line, match} = findLine /^(\s*for\s*\([^;]*;[^;]*;\s*)(([^+\)]+)\+\+)\s*\)/, line+1
        startPos = match[1].length
        messages.push {type: 'Error', text: "Use prefix increment ++#{match[3]}. It is never slower and sometimes faster", range:[[line,startPos], [line,startPos + match[2].length]]}
    return messages


runRules = ->
  messages = []
  for name of rules
    console.log name
    messages = messages.concat rules[name]() or []
  return messages


module.exports = LinterMoose =
  linterMooseView: null
  modalPanel: null
  subscriptions: null

  activate: ->
    require('atom-package-deps').install 'linter-moose'
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.config.observe 'linter-example.executablePath',
      (executablePath) =>
        @executablePath = executablePath

  deactivate: ->
    @subscriptions.dispose()

  provideLinter: ->
    provider =
      grammarScopes: ['source.c', 'source.cpp']
      scope: 'file' # or 'project'
      lintOnFly: true # must be false for scope: 'project'
      lint: (textEditor) ->
        # set the current editor
        editor = textEditor

        # set the current file extension
        path = textEditor.getPath()
        dotPos = path.lastIndexOf('.')
        if dotPos < 0
          extension = null
        else
          extension = path.substr dotPos

        # get the current editor text as an array of lines
        lines = editor.getText().split '\n'

        # build the message list by running all built-in rules
        runRules()
