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

rules =
  includeGuard: ->
    # only check .h files
    return unless extension is 'h'

    guardName = null

    # check the ifdef
    try
      {line, match} = findLine /^#([^\s]+)(\s+)(.*)/
      if match[1] != 'ifndef'
        return [{type: 'Error', text: 'Include guard must come first', range:[[line,0], [line,match[1].length+1]]}]
      guardName = match[3]
      startPos = match[1].length + match[2].length + 1
      guardNameRange = [[line,startPos], [line,startPos+guardName.length]]
    catch e
      return [{type: 'Error', text: 'No include guard found' + e.message, range:[[0,0], [0,1]]}]

    # check the define
    try
      {line, match} = findLine /^#([^\s]+)(\s+)(.*)/, line+1
      if match[1] != 'define'
        return [{type: 'Error', text: 'Define part of the include guard is missing', range:[[line,0], [line,match[1].length+1]]}]
      if guardName != match[3]
        startPos = match[1].length + match[2].length + 1
        return [{type: 'Error', text: 'Include guard define symbol names are not matching', range:[[line,startPos], [line,startPos+match[3].length+1]]}]
    catch
      return [{type: 'Error', text: 'Include guard incomplete', range:[[0,0], [0,1]]}]

    # check the endif

    # check the class name (use guardNameRange)

  spaceBeforeBrace: ->
    messages = []
    line = -1
    try
      loop
        {line} = findLine /^\s*\};?$/, line+1
        if line > 0 and /^\s*$/.test lines[line-1]
          messages.push {type: 'Error', text: 'No empty lines before closing braces', range:[[line-1,0], [line-1,1]]}
    return messages

  openBraceNewLine: ->
    messages = []
    line = -1
    try
      loop
        {line, match} = findLine /(^\s*)(.*)(\s*)\{(.*)$/, line+1
        bracePos = match[1].length + match[2].length + match[3].length
        if match[2] != ''
          messages.push {type: 'Warn', text: 'Opening braces should be on a new line', range:[[line,bracePos], [line,bracePos+1]]}
        if match[4] != ''
          messages.push {type: 'Warn', text: 'Opening braces should be followed by a new line', range:[[line,bracePos+1], [line,bracePos+1+match[4].length]]}
        if line+1 < lines.length and /^\s*$/.test lines[line+1]
          messages.push {type: 'Error', text: 'No empty lines after opening braces', range:[[line+1,0], [line+1,1]]}
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
    if not atom.packages.getLoadedPackage 'linter'
      atom.notifications.addError 'Linter package not found',
        detail: '[linter-moose] `linter` package not found. \
                 Please install https://github.com/AtomLinter/Linter'

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
          extension = path.substr dotPos+1

        # get the current editor text as an array of lines
        lines = editor.getText().split '\n'

        # build the message list by running all built-in rules
        runRules()
