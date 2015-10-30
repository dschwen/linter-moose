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
        {line, match} = findLine /^(.*\b(void|Real|RealGradient|int|long| & |bool| \* )\s+)([^\(\s]+)\(/, line+1
        if not isCamelCase match[3]
          startPos = match[1].length
          messages.push {type: 'Error', text: 'Member functions should use camelCase', range:[[line,startPos], [line,startPos + match[3].length]]}
    return messages

  includeGuard: ->
    # only check .h files
    return unless extension is '.h'

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
    if lines.length > 0 and lines[lines.length-1] != ''
      return [{type: 'Warning', text: 'End the file with a new line', range:[[0,0], [0,1]]}]
    if lines.length > 1
      match = /^#endif \/\/(.*)$/.exec lines[lines.length-2]
      if not match or match[1] != guardName
        return [{type: 'Warning', text: 'The closing #endif for the include guard should have the guard symbol as a C++-style comment', range:[[lines.length-2,0], [lines.length-2,1]]}]

    # check the class name (use guardNameRange)
    classFound = false
    line = -1
    try
      loop
        {line, match} = findLine /^\s*class\s+([^:\s<;]+)/, line+1
        if match[1].toUpperCase() + '_H' == guardName
          classFound = true
          break
    if not classFound
      return [{type: 'Error', text: 'Include guard should be CLASSNAME_H', range: guardNameRange}]

  spaceBeforeBrace: ->
    messages = []
    line = -1
    try
      loop
        {line} = findLine /^\s*\};?$/, line+1
        if line > 0 and /^\s*$/.test lines[line-1]
          messages.push {type: 'Error', text: 'No empty lines before closing braces', range:[[line-1,0], [line-1,1]]}
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

  operatorWhitespace: ->
    messages = []
    editor.scan /(.)(\s?)(\+|-|\/|\*|%|==|<|>|<=|>=|<|>|<<|>>|\+=|-=|,|\)|\()(\s?)/, (item) ->
      op = item.match[3]
      before = item.match[2] != ' '
      after  = item.match[4] != ' '

      # <> is ok (templates)
      if (op == '>' and item.match[1] == '<') or
         (op == '<' and item.match[5] == '>')
        return

      # // /* */ ** are ok (templates)
      if (op == '*' and item.match[1] == '/') or
         (op == '*' and item.match[5] == '/') or
         (op == '*' and item.match[5] == '*') or (op == '*' and item.match[1] == '*') or
         (op == '/' and item.match[5] == '/') or (op == '/' and item.match[1] == '/') or
         (op == '/' and item.match[5] == '*') or
         (op == '/' and item.match[1] == '*')
        return

      if (op == '(' and not after) or
         (op == ')' and not before)
        messages.push {type: 'Warning', text: 'No whitespace on the interior side of a brace', range:item.range}

      if op == ',' and after
        messages.push {type: 'Warning', text: 'Please leave whitespace after comma operators', range:item.range}

      if (op != '*' and (before or after)) or
         (op == '*' and not /[\(]/.test item.match[1].match and before) or
         (op == '*' and /[-+\/\*]/.test item.match[1].match and (before or after))
        messages.push {type: 'Error', text: 'Please leave whitespace around binary operators', range:item.range}

    return messages

  openBraceNewLine: ->
    messages = []
    line = -1
    try
      loop
        {line, match} = findLine /(^\s*)(.*)(\s*)\{(.*)$/, line+1
        bracePos = match[1].length + match[2].length + match[3].length

        # allow doxygen ///@{ and empty body {}
        continue if match[2] == '///@' or match[4] == '}'

        if match[2] != ''
          messages.push {type: 'Warning', text: 'Opening braces should be on a new line', range:[[line,bracePos], [line,bracePos+1]]}

        if match[4] != ''
          messages.push {type: 'Warning', text: 'Opening braces should be followed by a new line', range:[[line,bracePos+1], [line,bracePos+1+match[4].length]]}
        else if line+1 < lines.length and /^\s*$/.test lines[line+1]
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
