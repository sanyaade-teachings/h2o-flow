_assistance =
  importFiles:
    description: 'Import file(s) into H<sub>2</sub>O'
    icon: 'files-o'
  getFrames:
    description: 'Get a list of frames in H<sub>2</sub>O'
    icon: 'database'
  getModels:
    description: 'Get a list of models in H<sub>2</sub>O'
    icon: 'cubes'
  getJobs:
    description: 'Get a list of jobs running in H<sub>2</sub>O'
    icon: 'tasks'
  buildModel:
    description: 'Build a model'
    icon: 'cube'

H2O.Routines = (_) ->

  #TODO move these into Flow.Async
  _fork = (f, args...) -> Flow.Async.fork f, args
  _join = (args..., go) -> Flow.Async.join args, Flow.Async.applicate go
  _call = (go, args...) -> Flow.Async.join args, Flow.Async.applicate go
  _apply = (go, args) -> Flow.Async.join args, go
  _isFuture = Flow.Async.isFuture
  _async = Flow.Async.async
  _get = Flow.Async.get

  renderable = Flow.Async.renderable #XXX obsolete

  proceed = (func, args) ->
    renderable Flow.Async.noop, (ignore, go) ->
      go null, apply func, null, [_].concat args or []

  form = (controls, go) ->
    go null, signals controls or []

  gui = (controls) ->
    Flow.Async.renderable form, controls, (form, go) ->
      go null, Flow.Form _, form

  gui[name] = f for name, f of Flow.Gui

  help = -> proceed H2O.Help

  flow_ = (raw) ->
    raw._flow_ or raw._flow_ = _cache_: {}

  render_ = (raw, render) ->
    (flow_ raw).render = render
    raw

  inspect_ = (raw, inspectors) ->
    root = flow_ raw
    root.inspect = {} unless root.inspect?
    for attr, f of inspectors
      root.inspect[attr] = f
    raw

  inspect = (a, b) ->
    if arguments.length is 1
      inspect$1 a
    else
      inspect$2 a, b

  inspect$1 = (obj) ->
    if _isFuture obj
      _async inspect, obj
    else
      if inspectors = obj?._flow_?.inspect
        inspections = []
        for attr, f of inspectors
          inspections.push inspect$2 attr, obj
        render_ inspections, -> H2O.InspectsOutput _, inspections
        inspections
      else
        {}

  inspect$2 = (attr, obj) ->
    return unless attr
    return _async inspect, attr, obj if _isFuture obj
    return unless obj
    return unless root = obj._flow_
    return unless inspectors = root.inspect
    return cached if cached = root._cache_[ key = "inspect_#{attr}" ]
    return unless f = inspectors[attr]
    root._cache_[key] = inspection = f()
    render_ inspection, -> H2O.InspectOutput _, inspection
    inspection

  __plot = (config, go) ->
    Flow.Plot config, (error, plot) ->
      if error
        go new Flow.Error 'Error rendering plot.', error
      else
        go null, plot

  _plot = (config, go) ->
    if config.data
      if _isFuture config.data
        config.data (error, data) ->
          if error
            go new Flow.Error 'Error evaluating data for plot().', error
          else
            config.data = data
            __plot config, go
      else
        __plot config, go
    else
      go new Flow.Error "Cannot plot(): missing 'data'."

  plot = (config) ->
    renderable _plot, config, (plot, go) ->
      go null, H2O.PlotOutput _, plot

  plot.stack = Flow.Plot.stack

  grid = (data) ->
    plot
      type: 'text'
      data: data

  extensionSchemaConfig =
    column:
      integerDistribution: [
        [ 'intervalStart', TInteger ]
        [ 'intervalEnd', TInteger ]
        [ 'count', TInteger ]
      ]
      realDistribution: [
        [ 'intervalStart', TReal ]
        [ 'intervalEnd', TReal ]
        [ 'count', TInteger ]
      ]
    frame:
      columns: [
        [ 'label', TString ]
        [ 'missing', TInteger ]
        [ 'zeros', TInteger ]
        [ 'pinfs', TInteger ]
        [ 'ninfs', TInteger ]
        [ 'min', TReal ]
        [ 'max', TReal ]
        [ 'mean', TReal ]
        [ 'sigma', TReal ]
        [ 'type', TString ]
        [ 'domain', TInteger ]
        #[ 'data', TArray ]
        #[ 'str_data', TArray ]
        [ 'precision', TReal ]
      ]

  extensionSchemas = {}
  for groupName, group of extensionSchemaConfig
    extensionSchemas[groupName] = schemas = {}
    for schemaName, tuples of group
      attributes = for tuple in tuples
        [ label, type ] = tuple
        label: label
        type: type

      schemas[schemaName] =
        attributes: attributes
        attributeNames: map attributes, (attribute) -> attribute.label

  extendFrames = (frames) ->
    render_ frames, -> H2O.FramesOutput _, frames
    frames

  #TODO rename
  inspectMultimodelParameters = (models) -> ->
    leader = head models
    parameters = leader.parameters
    columns = for parameter in parameters
      switch parameter.type
        when 'enum', 'Frame', 'string', 'byte[]', 'short[]', 'int[]', 'long[]', 'float[]', 'double[]'
          Flow.Data.Factor parameter.label
        when 'byte', 'short', 'int', 'long', 'float', 'double'
          Flow.Data.Variable parameter.label, TReal
        when 'string[]'
          Flow.Data.Variable parameter.label, TArray
        when 'boolean'
          Flow.Data.Variable parameter.label, Flow.Data.Boolean
        else
          Flow.Data.Variable parameter.label, TObject

    Record = Flow.Data.compile columns

    rows = new Array models.length
    for model, i in models
      rows[i] = row = new Record()
      for parameter, j in model.parameters
        column = columns[j]
        row[column.label] = if column.type is TFactor
          column.read parameter.actual_value
        else
          parameter.actual_value

    modelKeys = (model.key for model in models)

    Flow.Data.Table
      label: 'parameters'
      description: "Parameters for models #{modelKeys.join ', '}"
      columns: columns
      rows: rows
      meta:
        origin: "getModels #{stringify modelKeys}"

  inspectModelParameters = (model) -> ->
    parameters = model.parameters
    columns = [
      Flow.Data.Variable 'label', TString
      Flow.Data.Variable 'type', TString
      Flow.Data.Variable 'level', TString
      Flow.Data.Variable 'actual_value', TObject
      Flow.Data.Variable 'default_value', TObject
    ]

    Record = Flow.Data.compile columns
    rows = new Array parameters.length
    for parameter, i in parameters
      rows[i] = row = new Record()
      for column in columns
        row[column.label] = parameter[column.label]

    Flow.Data.Table
      label: 'parameters'
      description: "Parameters for model '#{model.key}'" #TODO frame key
      columns: columns
      rows: rows
      meta:
        origin: "getModel #{stringify model.key}"

  extendKMeansModel = (model) ->
    inspect_ model,
      parameters: inspectModelParameters model

  extendDeepLearningModel = (model) ->
    inspect_ model,
      parameters: inspectModelParameters model
  
  extendGLMModel = (model) ->
    inspect_ model,
      parameters: inspectModelParameters model

  extendModel = (model) ->
    switch model.algo
      when 'kmeans'
        extendKMeansModel model
      when 'deeplearning'
        extendDeepLearningModel model
      when 'glm'
        extendGLMModel model

    render_ model, -> H2O.ModelOutput _, model

  extendModels = (models) ->
    for model in models
      extendModel model

    algos = unique (model.algo for model in models)
    if algos.length is 1
      inspect_ models,
        parameters: inspectMultimodelParameters models 

    render_ models, -> H2O.ModelsOutput _, models

  computeTruePositiveRate = (cm) ->
    [[tn, fp], [fn, tp]] = cm
    tp / (tp + fn)
    
  computeFalsePositiveRate = (cm) ->
    [[tn, fp], [fn, tp]] = cm
    fp / (fp + tn)

  read = (value) -> if value is 'NaN' then null else value

  extendPredictions = (predictions) ->
    

  extendPrediction = (prediction) ->
    { frame, model, auc } = prediction

    #threshold_criterion scalar
    #AUC scalar
    #Gini scalar

    #actual_domain 2

    inspectScores = ->
      columns = [
        thresholdsColumn = Flow.Data.Variable 'threshold', TReal
        f1Column = Flow.Data.Variable 'F1', TReal
        f2Column = Flow.Data.Variable 'F2', TReal
        f05Column = Flow.Data.Variable 'F0point5', TReal
        accuracyColumn = Flow.Data.Variable 'accuracy', TReal
        errorColumn = Flow.Data.Variable 'errorr', TReal
        precisionColumn = Flow.Data.Variable 'precision', TReal
        recallColumn = Flow.Data.Variable 'recall', TReal
        specificityColumn = Flow.Data.Variable 'specificity', TReal
        mccColumn = Flow.Data.Variable 'mcc', TReal
        mpceColumn = Flow.Data.Variable 'max_per_class_error', TReal
        cmColumn = Flow.Data.Variable 'confusion_matrices', TObject
        tprColumn = Flow.Data.Variable 'TPR', TReal
        fprColumn = Flow.Data.Variable 'FPR', TReal
      ]

      Record = Flow.Data.Record (column.label for column in columns)
      rows = for i in [ 0 ... auc.thresholds.length ]
        row = new Record()
        row.threshold = read auc.thresholds[i]
        row.F1 = read auc.F1[i]
        row.F2 = read auc.F2[i]
        row.F0point5 = read auc.F0point5[i]
        row.accuracy = read auc.accuracy[i]
        row.errorr = read auc.errorr[i]
        row.precision = read auc.precision[i]
        row.recall = read auc.recall[i]
        row.specificity = read auc.specificity[i]
        row.mcc = read auc.mcc[i]
        row.max_per_class_error = read auc.max_per_class_error[i]
        row.confusion_matrices = cm = auc.confusion_matrices[i]
        row.TPR = computeTruePositiveRate cm
        row.FPR = computeFalsePositiveRate cm
        row

      Flow.Data.Table
        label: 'metrics'
        description: "Metrics for model '#{model.key}' on frame '#{frame.key.name}'"
        columns: columns
        rows: rows
        meta:
          origin: "getPrediction #{stringify model.key}, #{stringify frame.key.name}"

    inspectMetrics = ->
      
      [ criteriaDomain, criteriaData ] = Flow.Data.factor auc.threshold_criteria

      columns = [
        criteriaColumn = Flow.Data.Variable 'criteria', TFactor, criteriaDomain
        thresholdColumn = Flow.Data.Variable 'threshold', TReal
        f1Column = Flow.Data.Variable 'F1', TReal
        f2Column = Flow.Data.Variable 'F2', TReal
        f05Column = Flow.Data.Variable 'F0point5', TReal
        accuracyColumn = Flow.Data.Variable 'accuracy', TReal
        errorColumn = Flow.Data.Variable 'error', TReal
        precisionColumn = Flow.Data.Variable 'precision', TReal
        recallColumn = Flow.Data.Variable 'recall', TReal
        specificityColumn = Flow.Data.Variable 'specificity', TReal
        mccColumn = Flow.Data.Variable 'mcc', TReal
        mpceColumn = Flow.Data.Variable 'max_per_class_error', TReal
        cmColumn = Flow.Data.Variable 'confusion_matrix', TObject
        tprColumn = Flow.Data.Variable 'TPR', TReal
        fprColumn = Flow.Data.Variable 'FPR', TReal
      ]

      Record = Flow.Data.Record (column.label for column in columns)
      rows = for i in [ 0 ... auc.threshold_criteria.length ]
        row = new Record()
        row.criteria = criteriaData[i]
        row.threshold = read auc.threshold_for_criteria[i]
        row.F1 = read auc.F1_for_criteria[i]
        row.F2 = read auc.F2_for_criteria[i]
        row.F0point5 = read auc.F0point5_for_criteria[i]
        row.accuracy = read auc.accuracy_for_criteria[i]
        row.error = read auc.error_for_criteria[i]
        row.precision = read auc.precision_for_criteria[i]
        row.recall = read auc.recall_for_criteria[i]
        row.specificity = read auc.specificity_for_criteria[i]
        row.mcc = read auc.mcc_for_criteria[i]
        row.max_per_class_error = read auc.max_per_class_error_for_criteria[i]
        row.confusion_matrix = cm = auc.confusion_matrix_for_criteria[i] 
        row.TPR = computeTruePositiveRate cm
        row.FPR = computeFalsePositiveRate cm
        row

      Flow.Data.Table
        label: 'scores'
        description: "Scores for model '#{prediction.model.key}' on frame '#{prediction.frame.key.name}'"
        columns: columns
        rows: rows
        meta:
          origin: "getPrediction #{stringify model.key}, #{stringify frame.key.name}"
    
    render_ prediction, -> H2O.PredictOutput _, prediction
    inspect_ prediction,
      scores: inspectScores
      metrics: inspectMetrics

  extendFrame = (frameKey, frame) ->
    inspectColumns = ->
      schema = extensionSchemas.frame.columns
      Record = Flow.Data.Record schema.attributeNames
      rows = for column in frame.columns
        row = new Record()
        for attr in schema.attributeNames
          switch attr
            when 'min'
              row[attr] = head column.mins
            when 'max'
              row[attr] = head column.maxs
            when 'domain'
              row[attr] = if domain = column[attr] then domain.length else null
            else
              row[attr] = column[attr] 
        row

      Flow.Data.Table
        label: 'columns'
        description: 'A list of columns in the H2O Frame.'
        columns: schema.attributes
        rows: rows
        meta:
          origin: "getFrame #{stringify frameKey}"

    inspectData = ->
      frameColumns = frame.columns
      columns = for column in frameColumns
        #XXX format functions
        switch column.type
          when 'int'
            label: column.label
            type: TInteger
          when 'real'
            label: column.label
            type: TReal
          when 'enum'
            label: column.label
            type: TFactor
            domain: column.domain
          when 'uuid', 'string'
            label: column.label
            type: TString
          when 'time'
            label: column.label
            type: TDate
          else
            throw new Error "Invalid column type #{column.type} found in frame #{frameKey}."
      columnNames = (column.label for column in columns)
      Record = Flow.Data.Record columnNames
      rowCount = (head frame.columns).data.length
      rows = for i in [0 ... rowCount]
        row = new Record()
        for column, j in columns
          value = frameColumns[j].data[i]
          switch column.type
            when TInteger, TReal
              #TODO handle +-Inf
              row[column.label] = if value is 'NaN' then null else value
            else
              row[column.label] = value
        row
      
      Flow.Data.Table
        label: 'data'
        description: 'A partial list of rows in the H2O Frame.'
        columns: columns
        rows: rows
        meta:
          origin: "getFrame #{stringify frameKey}"

    inspect_ frame,
      columns: inspectColumns
      data: inspectData

  extendColumnSummary = (frameKey, frame, columnName) ->
    column = head frame.columns
    rowCount = frame.rows

    inspectPercentiles = ->
      percentiles = frame.default_pctiles
      percentileValues = column.pctiles

      columns = [
        label: 'percentile'
        type: TReal
      ,
        label: 'value'
        type: TReal #TODO depends on type of column?
      ]

      Record = Flow.Data.Record map columns, (column) -> column.label
      rows = for percentile, i in percentiles
        row = new Record()
        row.percentile = percentile
        row.value = percentileValues[i]
        row

      Flow.Data.Table
        label: 'percentiles'
        description: "Percentiles for column '#{column.label}' in frame '#{frameKey}'."
        columns: columns
        rows: rows
        meta:
          origin: "getColumnSummary #{stringify frameKey}, #{stringify columnName}"


    inspectDistribution = ->
      distributionDataType = if column.type is 'int' then TInteger else TReal
      
      schema = if column.type is 'int' then extensionSchemas.column.integerDistribution else extensionSchemas.column.realDistribution
      Record = Flow.Data.Record schema.attributeNames
      
      minBinCount = 32
      { base, stride, bins } = column
      width = Math.floor bins.length / minBinCount
      interval = stride * width
      
      rows = []
      if width > 0
        binCount = minBinCount + if bins.length % width > 0 then 1 else 0
        for i in [0 ... binCount]
          m = i * width
          n = m + width
          count = 0
          for binIndex in [m ... n] when n < bins.length
            count += bins[binIndex]

          row = new Record()
          row.intervalStart = base + i * interval
          row.intervalEnd = row.intervalStart + interval
          row.count = count
          rows.push row
      else
        for count, i in bins
          row = new Record()
          row.intervalStart = base + i * stride
          row.intervalEnd = row.intervalStart + stride
          row.count = count
          rows.push row

      Flow.Data.Table
        label: 'distribution'
        description: "Distribution for column '#{column.label}' in frame '#{frameKey}'."
        columns: schema.attributes
        rows: rows
        meta:
          origin: "getColumnSummary #{stringify frameKey}, #{stringify columnName}"

    inspectCharacteristics = ->
      { missing, zeros, pinfs, ninfs } = column
      other = rowCount - missing - zeros - pinfs - ninfs

      [ domain, characteristics ] = Flow.Data.factor [ 'Missing', '-Inf', 'Zero', '+Inf', 'Other' ]

      columns = [
        label: 'characteristic'
        type: TFactor
        domain: domain
      ,
        label: 'count'
        type: TInteger
        domain: [ 0, rowCount ]
      ,
        label: 'percent'
        type: TReal
        domain: [ 0, 100 ]
      ]

      rows = for count, i in [ missing, ninfs, zeros, pinfs, other ]
        characteristic: characteristics[i]
        count: count
        percent: 100 * count / rowCount

      Flow.Data.Table
        label: 'characteristics'
        description: "Characteristics for column '#{column.label}' in frame '#{frameKey}'."
        columns: columns
        rows: rows
        meta:
          origin: "getColumnSummary #{stringify frameKey}, #{stringify columnName}"
          plot: """
          plot
            title: 'Characteristics for #{frameKey} : #{column.label}'
            type: 'interval'
            data: inspect 'characteristics', getColumnSummary #{stringify frameKey}, #{stringify columnName}
            x: plot.stack 'count'
            color: 'characteristic'
          """

    inspectSummary = ->
      columns = [
        label: 'mean'
        type: TReal
      ,
        label: 'q1'
        type: TReal
      ,
        label: 'q2'
        type: TReal
      ,
        label: 'q3'
        type: TReal
      ,
        label: 'outliers'
        type: TArray
      ]

      defaultPercentiles = frame.default_pctiles
      percentiles = column.pctiles

      mean = column.mean
      q1 = percentiles[defaultPercentiles.indexOf 0.25]
      q2 = percentiles[defaultPercentiles.indexOf 0.5]
      q3 = percentiles[defaultPercentiles.indexOf 0.75]
      outliers = unique concat column.mins, column.maxs

      row =
        mean: mean
        q1: q1
        q2: q2
        q3: q3
        outliers: outliers

      Flow.Data.Table
        label: 'summary'
        description: "Summary for column '#{column.label}' in frame '#{frameKey}'."
        columns: columns
        rows: [ row ]
        meta:
          origin: "getColumnSummary #{stringify frameKey}, #{stringify columnName}"

    inspectDomain = ->
      levels = map column.bins, (count, index) -> count: count, index: index

      #TODO sort table in-place when sorting is implemented
      sortedLevels = sortBy levels, (level) -> -level.count

      labelColumn = 
        label: 'label'
        type: TFactor
        domain: column.domain
      countColumn = 
        label: 'count'
        type: TInteger
        domain: null
      percentColumn =
        label: 'percent'
        type: TReal
        domain: [ 0, 100 ]

      columns = [ labelColumn, countColumn, percentColumn ]

      Record = Flow.Data.Record map columns, (column) -> column.label
      rows = for level in sortedLevels
        row = new Record()
        row.label = level.index
        row.count = level.count
        row.percent = 100 * level.count / rowCount
        row

      countColumn.domain = Flow.Data.computeRange rows, 'count'
      
      Flow.Data.Table
        label: 'domain'
        description: "Domain for column '#{column.label}' in frame '#{frameKey}'."
        columns: columns
        rows: rows
        meta:
          origin: "getColumnSummary #{stringify frameKey}, #{stringify columnName}"
          plot: """
          plot
            title: 'Domain for #{frameKey} : #{column.label}'
            type: 'interval'
            data: inspect 'domain', getColumnSummary #{stringify frameKey}, #{stringify columnName}
            x: 'count'
            y: 'label'
          """

    switch column.type
      when 'int', 'real'
        inspect_ frame,
          characteristics: inspectCharacteristics
          summary: inspectSummary
          distribution: inspectDistribution
          percentiles: inspectPercentiles
      else
        inspect_ frame,
          characteristics: inspectCharacteristics
          domain: inspectDomain
          percentiles: inspectPercentiles


  requestFrame = (frameKey, go) ->
    _.requestFrame frameKey, (error, frame) ->
      if error
        go error
      else
        go null, extendFrame frameKey, frame

  requestColumnSummary = (frameKey, columnName, go) ->
    _.requestColumnSummary frameKey, columnName, (error, frame) ->
      if error
        go error
      else
        go null, extendColumnSummary frameKey, frame, columnName

  requestFrames = (go) ->
    _.requestFrames (error, frames) ->
      if error
        go error
      else
        go null, extendFrames frames

  getFrames = ->
    _fork requestFrames  

  getFrame = (frameKey) ->
    switch typeOf frameKey
      when 'String'
        renderable requestFrame, frameKey, (frame, go) ->
          go null, H2O.FrameOutput _, frame
      else
        assist getFrame

  getColumnSummary = (frameKey, columnName) ->
    renderable requestColumnSummary, frameKey, columnName, (frame, go) ->
      go null, H2O.ColumnSummaryOutput _, frameKey, frame, columnName

  requestModels = (go) ->
    _.requestModels (error, models) ->
      if error then go error else go null, extendModels models

  requestModelsByKeys = (modelKeys, go) ->
    futures = for key in modelKeys
      _fork _.requestModel, key
    Flow.Async.join futures, (error, models) ->
      if error then go error else go null, extendModels models

  getModels = (modelKeys) ->
    if isArray modelKeys
      if modelKeys.length
        _fork requestModelsByKeys, modelKeys     
      else
        _fork requestModels 
    else
      _fork requestModels

  requestModel = (modelKey, go) ->
    _.requestModel modelKey, (error, model) ->
      if error then go error else go null, extendModel model

  getModel = (modelKey) ->
    switch typeOf modelKey
      when 'String'
        _fork requestModel, modelKey
      else
        assist getModel

  getJobs = ->
    renderable _.requestJobs, (jobs, go) ->
      go null, H2O.JobsOutput _, jobs    

  getJob = (arg) ->
    switch typeOf arg
      when 'String'
        renderable _.requestJob, arg, (job, go) ->
          go null, H2O.JobOutput _, job
      when 'Object'
        if arg.key?
          getJob arg.key
        else
          assist getJob
      else
        assist getJob

  importFiles = (paths) ->
    switch typeOf paths
      when 'Array'
        renderable _.requestImportFiles, paths, (importResults, go) ->
          go null, H2O.ImportFilesOutput _, importResults
      else
        assist importFiles

  setupParse = (sourceKeys) ->
    switch typeOf sourceKeys
      when 'Array'
        renderable _.requestParseSetup, sourceKeys, (parseSetupResults, go) ->
          go null, H2O.SetupParseOutput _, parseSetupResults
      else
        assist setupParse

  parseRaw = (opts) -> #XXX review args
    #XXX validation

    sourceKeys = opts.srcs
    destinationKey = opts.hex
    parserType = opts.pType
    separator = opts.sep
    columnCount = opts.ncols
    useSingleQuotes = opts.singleQuotes
    columnNames = opts.columnNames
    deleteOnDone = opts.delete_on_done
    checkHeader = opts.checkHeader

    renderable _.requestParseFiles, sourceKeys, destinationKey, parserType, separator, columnCount, useSingleQuotes, columnNames, deleteOnDone, checkHeader, (parseResult, go) ->
      go null, H2O.ParseOutput _, parseResult

  buildModel = (algo, opts) ->
    if algo and opts and keys(opts).length > 1
      renderable _.requestModelBuild, algo, opts, (result, go) ->
        go null, H2O.JobOutput _, head result.jobs
    else
      assist buildModel, algo, opts

  requestPredict = (modelKey, frameKey, go) ->
    _.requestPredict modelKey, frameKey, (error, prediction) ->
      if error
        go error
      else
        go null, extendPrediction prediction

  predict = (modelKey, frameKey) ->
    if modelKey and frameKey
      _fork requestPredict, modelKey, frameKey
    else
      assist predict, modelKey, frameKey

  requestPredictions = (modelKey, frameKey, go) ->
    _.requestPredictions modelKey, frameKey, (error, predictions) ->
      if error
        go error
      else
        if modelKey and frameKey
          go null, extendPrediction head predictions
        else
          go null, extendPredictions predictions

  getPrediction = (modelKey, frameKey) ->
    if modelKey and frameKey
      _fork requestPredictions, modelKey, frameKey
    else
      assist requestPredictions, modelKey, frameKey

  getPredictions = (opts={}) ->
    { frame:frameKey, model:modelKey } = opts
    _fork requestPredictions, modelKey, frameKey 

  loadScript = (path, go) ->
    onDone = (script, status) -> go null, script:script, status:status
    onFail = (jqxhr, settings, error) -> go error #TODO use framework error

    $.getScript path
      .done onDone
      .fail onFail

  assist = (func, args...) ->
    if func is undefined
      proceed H2O.Assist, [ _assistance ]
    else
      switch func
        when importFiles
          proceed H2O.ImportFilesInput
        when buildModel
          proceed H2O.ModelInput, args
        when predict
          proceed H2O.PredictInput, args
        else
          proceed H2O.NoAssistView

  link _.ready, ->
    link _.inspect, inspect

  # fork/join 
  fork: _fork
  join: _join
  call: _call
  apply: _apply
  isFuture: _isFuture
  #
  # Dataflow
  signal: signal
  signals: signals
  isSignal: isSignal
  act: act
  react: react
  lift: lift
  merge: merge
  #
  # Generic
  inspect: inspect
  plot: plot
  grid: grid
  get: _get
  #
  # Meta
  assist: assist
  help: help
  #
  # GUI
  gui: gui
  #
  # Util
  loadScript: loadScript
  #
  # H2O
  getJobs: getJobs
  getJob: getJob
  importFiles: importFiles
  setupParse: setupParse
  parseRaw: parseRaw
  getFrames: getFrames
  getFrame: getFrame
  getColumnSummary: getColumnSummary
  buildModel: buildModel
  getModels: getModels
  getModel: getModel
  predict: predict
  getPrediction: getPrediction
  getPredictions: getPredictions

