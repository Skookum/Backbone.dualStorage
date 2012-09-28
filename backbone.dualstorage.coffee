'use strict'
console =
  log: ->

# A simple module to replace `Backbone.sync` with *localStorage*-based
# persistence. Models are given GUIDS, and saved into a JSON object. Simple
# as that.

# Make it easy for collections to sync dirty and destroyed records
# Simply call collection.syncDirtyAndDestroyed()
Backbone.Collection.prototype.syncDirty = (cb)->
  cb ?= ()->
  storeName = @storeName or @url
  store = localStorage.getItem "#{storeName}_dirty"
  ids = (store and store.split(',')) or []
  total = ids.length
  errored = []
  synced = []
  queue = []
  next = ->
    return cb(errored, synced) if ids.length == 0
    sync ids.shift()
  error = (model)->
    errored.push(model)
    next()
  success = (model)->
    # if model is still dirty, sync was not successful
    if model.dirty then errored.push(model) else synced.push(model)
    next()
  sync = (id)=>
    model = if id.length == 44 then @where(id: id)[0] else @get(id)
    @trigger 'sync:status', current: model, total: total, synced: synced.length, errored: errored.length
    return error(id) if !model
    model.save({}, { success: success, error: error })
  next()

Backbone.Collection.prototype.syncDestroyed = (cb)->
  cb ?= ()->
  storeName = @storeName or @url
  store = localStorage.getItem "#{storeName}_destroyed"
  ids = (store and store.split(',')) or []
  
  total = ids.length
  errored = []
  synced = []
  queue = []
  next = ->
    return cb(errored, synced) if ids.length == 0
    sync ids.shift()
  error = (model)->
    errored.push(model)
    next()
  success = (model)->
    # if model is still dirty, sync was not successful
    if model.dirty then errored.push(model) else synced.push(model)
    next()
  sync = (id)=>
    model = new @model({id: id})
    @trigger 'sync:status', current: model, total: total, synced: synced.length, errored: errored.length
    model.collection = @
    model.destroy({ success: success, error: error })
  next()

Backbone.Collection.prototype.syncDirtyAndDestroyed = (cb)->
  cb ?= ()->
  @syncDirty (errored, synced)=>
    @syncDestroyed (errored2, synced2)=>
      errored.push.apply(errored, errored2)
      synced.push.apply(synced, synced2)
      cb(errored, synced)

Backbone.Collection::dirtyCount = ->
  @dirtyIds().length

Backbone.Collection::dirtyIds = ->
  storeName = @storeName or @url
  store = localStorage.getItem "#{storeName}_dirty"
  dirty_ids = (store and store.split(',')) or []
  store = localStorage.getItem "#{storeName}_destroyed"
  destroyed_ids = (store and store.split(',')) or []
  return _.union(dirty_ids, destroyed_ids)

Backbone.Collection::pullData = (options={})->
  options.populateCollection = false
  success = options.success
  options.success = (collection, resp)=>
    console.log 'updateReady', @storeName or @url
    @trigger 'updateReady', this, resp
    success.apply this, arguments if success
  @fetch options

# fetch collection from the local store, waiting for the sync to complete first
# if necessary
Backbone.Collection::fetchLocal = (options={})->
  options.remote = false
  success = options.success
  storeName = @storeName or @url
  doFetch = =>
    options.success = =>
      success.apply(this, arguments) if success
    @fetch options
  #@on 'fetchedIntoLocalstorage', _.once -> doFetch()
  doFetch()

Backbone.Collection::_localstorageWatchCount = 0
Backbone.Collection::watchForLocalUpdates = ->
  @_localstorageWatchCount++
  if @_localstorageWatchCount == 1
    @on 'updateReady', (c) =>
      @fetchLocal()
    @fetchLocal()

Backbone.Collection::unwatchLocalUpdates = ->
  if @_localstorageWatchCount <= 0 || --@_localstorageWatchCount > 0
    return
  @off 'updateReady'
  @reset []

# Generate four random hex digits.
S4 = ->
  (((1 + Math.random()) * 0x10000) | 0).toString(16).substring 1

# Our Store is represented by a single JS object in *localStorage*. Create it
# with a meaningful name, like the name you'd give a table.
class window.Store
  sep: '' # previously '-'

  constructor: (name) ->
    @name = name
    @records = @recordsOn @name
    @recordsNoCollection = @recordsOn @name + '_nocollection'

  # Generates an unique id to use when saving new instances into localstorage
  # by default generates a pseudo-GUID by concatenating random hexadecimal.
  # you can overwrite this function to use another strategy
  generateId: ->
    S4() + S4() + '-' + S4() + '-' + S4() + '-' + S4() + '-' + S4() + S4() + S4() + S4() + S4()
  
  # Save the current state of the **Store** to *localStorage*.
  save: ->
    localStorage.setItem @name, @records.join(',')
    localStorage.setItem @name + '_nocollection', _.uniq(@recordsNoCollection).join(',')
  
  recordsOn: (key) ->
    store = localStorage.getItem(key)
    (store and store.split(',')) or []
  
  dirty: (model) ->
    dirtyRecords = @recordsOn @name + '_dirty'
    if not _.include(dirtyRecords, model.id.toString())
      console.log 'dirtying', model
      dirtyRecords.push model.id
      localStorage.setItem @name + '_dirty', dirtyRecords.join(',')
    model.dirty = true
    model
  
  clean: (model, from) ->
    store = "#{@name}_#{from}"
    dirtyRecords = @recordsOn store
    if _.include dirtyRecords, model.id.toString()
      console.log 'cleaning', model.id
      localStorage.setItem store, _.without(dirtyRecords, model.id.toString()).join(',')
    model.dirty = false
    model
    
  destroyed: (model) ->
    destroyedRecords = @recordsOn @name + '_destroyed'
    if not _.include destroyedRecords, model.id.toString()
      destroyedRecords.push model.id
      localStorage.setItem @name + '_destroyed', destroyedRecords.join(',')
    model
    
  # Add a model, giving it a (hopefully)-unique GUID, if it doesn't already
  # have an id of it's own.
  create: (model, storeInCollection = true) ->
    if model instanceof Backbone.Model
      model = model.toJSON()
    console.log 'creating', model, 'in', @name
    if not _.isObject(model) then return model
    #if model.attributes? then model = model.attributes #removed to fix issue 14
    if not model.id
      model.id = @generateId()
      #model.set model.idAttribute, model.id
    localStorage.setItem @name + @sep + model.id, JSON.stringify(model)
    if storeInCollection
      console.log "storing model #{model.id} in collection #{@name}" 
      @records.push model.id.toString()
    else
      @recordsNoCollection.push model.id.toString()
    @save()
    model

  # Update a model by replacing its copy in `this.data`.
  update: (model) ->
    console.log 'updating', model, 'in', @name
    localStorage.setItem @name + @sep + model.id, JSON.stringify(model)
    if not _.include(@records, model.id.toString())
      @records.push model.id.toString()
    @save()
    model
  
  clear: ->
    for id in @records
      localStorage.removeItem @name + @sep + id
    @records = []
    @save()
  
  clearNoCollection: ->
    for id in @recordsNoCollection
      localStorage.removeItem @name + @sep + id
    @recordsNoCollection = []
    @save()
  
  hasDirtyOrDestroyed: ->
    not _.isEmpty(localStorage.getItem(@name + '_dirty')) or not _.isEmpty(localStorage.getItem(@name + '_destroyed'))

  # Retrieve a model from `this.data` by id.
  find: (model) ->
    console.log 'finding', model, 'in', @name
    JSON.parse localStorage.getItem(@name + @sep + model.id)
  
  findIds: (ids) ->
    console.log 'finding ids', ids, 'in', @name
    for id in ids
      JSON.parse localStorage.getItem(@name + @sep + id)

  # Return the array of all models currently in storage.
  findAll: (storeSuffix)->
    console.log 'findAlling'
    records = if storeSuffix == 'nocollection' then @recordsNoCollection else @records
    for id in records
      JSON.parse localStorage.getItem(@name + @sep + id)

  # Delete a model from `this.data`, returning it.
  destroy: (model) ->
    console.log 'trying to destroy', model, 'in', @name
    localStorage.removeItem @name + @sep + model.id
    @records = _.reject(@records, (record_id) ->
      record_id is model.id.toString()
    )
    @save()
    model

# Override `Backbone.sync` to use delegate to the model or collection's
# *localStorage* property, which should be an instance of `Store`.
localsync = (method, model, options) ->
  store = new Store options.storeName

  response = switch method
    when 'read'
      if options.onlyIds
        store.findIds(options.onlyIds)
      else
        if model.id then store.find(model) else store.findAll(options.storeSuffix)
    when 'hasDirtyOrDestroyed'
      store.hasDirtyOrDestroyed()
    when 'clear'
      store.clear()
    when 'clearNoCollection'
      store.clearNoCollection()
    when 'create'
      skipCollection = options.skipCollection || false
      model = store.create(model, !skipCollection)
      store.dirty(model) if options.dirty
    when 'update'
      store.update(model)
      if options.dirty then store.dirty(model) else store.clean(model, 'dirty')
    when 'delete'
      store.destroy(model)
      if options.dirty
        store.destroyed(model)
      else
        if model.id.toString().length == 44 
          store.clean(model, 'dirty')
        else
          store.clean(model, 'destroyed')
  
  unless options.ignoreCallbacks
    if response
      options.success response
    else
      options.error 'Record not found'
  
  response

# If the value of the named property is a function then invoke it;
# otherwise, return it.
# based on _.result from underscore github
result = (object, property) ->
  return null unless object
  value = object[property]
  if _.isFunction(value) then value.call(object) else value

# Helper function to run parseBeforeLocalSave() in order to
# parse a remote JSON response before caching locally
parseRemoteResponse = (object, response) ->
  if not (object and object.parseBeforeLocalSave) then return response
  if _.isFunction(object.parseBeforeLocalSave) then object.parseBeforeLocalSave(response)

onlineSync = Backbone.sync

dualsync = (method, model, options) ->
  console.log 'dualsync', method, model, options
  populateCollection = options.populateCollection ? true
  
  options.storeName = result(model.collection, 'storeName') || result(model, 'storeName') || 
                      result(model.collection, 'url') || result(model, 'url')
  
  # execute only online sync
  if result(model, 'remote') or result(model.collection, 'remote') or options.local is false
    console.log "only doing online sync"
    return onlineSync(method, model, options)
  
  # execute only local sync
  local = result(model, 'local') or result(model.collection, 'local')
  options.dirty = options.remote is false and not local
  if options.remote is false or local
    options.ignoreCallbacks = false
    console.log "only syncing locally"
    return localsync(method, model, options)
  
  # execute dual sync
  options.ignoreCallbacks = true
  
  success = options.success
  error = options.error
  
  switch method
    when 'read'
      # set the "add" flag to true because we're not going to be changing the
      # collection (i.e. we're adding 0 elements)
      if !populateCollection then options.add = true
      if localsync('hasDirtyOrDestroyed', model, options)
        model.trigger 'fetchRequested', model
        console.log "can't clear", options.storeName, "require sync dirty data first"
        model.fromLocal = true
        if populateCollection 
          success localsync(method, model, options)
        else
          success []
      else
        options.success = (resp, status, xhr) ->
          console.log 'got remote', resp, 'putting into', options.storeName
          resp = parseRemoteResponse(model, resp)
          model.fromLocal = false
          
          localsync('clear', model, options) unless options.skipCollection
          localsync('clearNoCollection', model, options)
          
          if _.isArray resp
            for i in resp
              console.log 'trying to store', i
              localsync('create', i, options)
          else
            localsync('create', resp, options)
          
          if !populateCollection
            resp = []
          success(resp, status, xhr)
        
        options.error = (resp) ->
          console.log 'getting local from', options.storeName
          model.fromLocal = true
          if !populateCollection
            success []
          else
            success localsync(method, model, options)

        onlineSync(method, model, options)

    when 'create'
      options.success = (resp, status, xhr) ->
        localsync(method, resp, options)
        success(resp, status, xhr)
      options.error = (resp) ->
        options.dirty = true
        success localsync(method, model, options)
      
      onlineSync(method, model, options)

    when 'update'
      if _.isString(model.id) and model.id.length == 44
        originalModel = model.clone()
        
        options.success = (resp, status, xhr) ->
          localsync('delete', originalModel, options)
          localsync('create', resp, options)
          success(resp, status, xhr)
        options.error = (resp) ->
          options.dirty = true
          success localsync(method, originalModel, options)
        
        model.set id: null
        onlineSync('create', model, options)
      else
        options.success = (resp, status, xhr) ->
          success localsync(method, model, options), 'success'
        options.error = (resp) ->
          options.dirty = true
          success localsync(method, model, options)
        
        onlineSync(method, model, options)

    when 'delete'
      if _.isString(model.id) and model.id.length == 44
        localsync(method, model, options)
      else
        options.success = (resp, status, xhr) ->
          localsync(method, model, options)
          success(resp, status, xhr)
        options.error = (resp) ->
          options.dirty = true
          success localsync(method, model, options)
        
        onlineSync(method, model, options)
    
Backbone.sync = dualsync
