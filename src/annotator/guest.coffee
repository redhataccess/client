baseURI = require('document-base-uri')
extend = require('extend')
raf = require('raf')
scrollIntoView = require('scroll-into-view')
CustomEvent = require('custom-event')

Delegator = require('./delegator')
$ = require('jquery')

adder = require('./adder')
highlighter = require('./highlighter')
rangeUtil = require('./range-util')
selections = require('./selections')
xpathRange = require('./anchoring/range')

polyglot = require('../shared/polyglot');

getProperClassName = require('../shared/util/get-proper-classname');

animationPromise = (fn) ->
  return new Promise (resolve, reject) ->
    raf ->
      try
        resolve(fn())
      catch error
        reject(error)

# Normalize the URI for an annotation. This makes it absolute and strips
# the fragment identifier.
normalizeURI = (uri, baseURI) ->
  # Convert to absolute URL
  url = new URL(uri, baseURI)
  # Remove the fragment identifier.
  # This is done on the serialized URL rather than modifying `url.hash` due
  # to a bug in Safari.
  # See https://github.com/hypothesis/h/issues/3471#issuecomment-226713750
  return url.toString().replace(/#.*/, '');

module.exports = class Guest extends Delegator
  SHOW_HIGHLIGHTS_CLASS = 'annotator-highlights-always-on'

  # Events to be bound on Delegator#element.
  events:
    ".annotator-hl click":               "onHighlightClick"
    ".annotator-hl mouseover":           "onHighlightMouseover"
    ".annotator-hl mouseout":            "onHighlightMouseout"
    "click":                             "onElementClick"
    "touchstart":                        "onElementTouchStart"

  options:
    Document: {}
    TextSelection: {}

  # Anchoring module
  anchoring: require('./anchoring/html')

  # Internal state
  plugins: null
  anchors: null
  visibleHighlights: false
  frameIdentifier: null
  enableClick: false

  html:
    adder: '<hypothesis-adder></hypothesis-adder>'

  constructor: (element, config) ->
    super

    this.adder = $(this.html.adder).appendTo(@element).hide()

    self = this
    this.adderCtrl = new adder.Adder(@adder[0], {
      onAnnotate: ->
        self.createAnnotation()
        document.getSelection().removeAllRanges()
      onHighlight: ->
        self.setVisibleHighlights(true)
        self.createHighlight()
        document.getSelection().removeAllRanges()
      # Managing the visibility of highlight Button in the adder.
      isHighlightBtnVisible: ->
        return config.isHighlightBtnVisible
      traslatedBtnStrings: ->
        return {'AnnotateBtn' : polyglot().t('Add Feedback'), 'HighlightBtn': polyglot().t('Highlight')}
    })
    this.selections = selections(document).subscribe
      next: (range) ->
        if range
          self._onSelection(range, config)
        else
          self._onClearSelection()

    this.plugins = {}
    this.anchors = []

    # Set the frame identifier if it's available.
    # The "top" guest instance will have this as null since it's in a top frame not a sub frame
    this.frameIdentifier = config.subFrameIdentifier || null

    # When enableClick is false, clicking (or tabbing around on mobile)
    # outside of the elements on the guest page doesn't close the sidebar
    this.enableClick = config.onElementClick || false ;

    cfOptions =
      config: config
      on: (event, handler) =>
        this.subscribe(event, handler)
      emit: (event, args...) =>
        this.publish(event, args)

    this.addPlugin('CrossFrame', cfOptions)
    @crossframe = this.plugins.CrossFrame

    @crossframe.onConnect(=> this._setupInitialState(config))
    this._connectAnnotationSync(@crossframe)
    this._connectAnnotationUISync(@crossframe, config)

    # Load plugins
    for own name, opts of @options
      if not @plugins[name] and @options.pluginClasses[name]
        this.addPlugin(name, opts)

  addPlugin: (name, options) ->
    if @plugins[name]
      console.error("You cannot have more than one instance of any plugin.")
    else
      klass = @options.pluginClasses[name]
      if typeof klass is 'function'
        @plugins[name] = new klass(@element[0], options)
        @plugins[name].annotator = this
        @plugins[name].pluginInit?()
      else
        console.error("Could not load " + name + " plugin. Have you included the appropriate <script> tag?")
    this # allow chaining

  # Get the document info
  getDocumentInfo: ->
    if @plugins.PDF?
      metadataPromise = Promise.resolve(@plugins.PDF.getMetadata())
      uriPromise = Promise.resolve(@plugins.PDF.uri())
    else if @plugins.Document?
      uriPromise = Promise.resolve(@plugins.Document.uri())
      metadataPromise = Promise.resolve(@plugins.Document.metadata)
    else
      uriPromise = Promise.reject()
      metadataPromise = Promise.reject()

    uriPromise = uriPromise.catch(-> decodeURIComponent(window.location.href))
    metadataPromise = metadataPromise.catch(-> {
      title: document.title
      link: [{href: decodeURIComponent(window.location.href)}]
    })

    return Promise.all([metadataPromise, uriPromise]).then ([metadata, href]) =>
      return {
        uri: normalizeURI(href, baseURI),
        metadata,
        frameIdentifier: this.frameIdentifier
      }

  _setupInitialState: (config) ->
    this.publish('panelReady')
    # this.setVisibleHighlights(config.showHighlights == 'always')
    # We load the page highlights off
    this.setVisibleHighlights(false)

  _connectAnnotationSync: (crossframe) ->
    this.subscribe 'annotationDeleted', (annotation) =>
      this.detach(annotation)

    this.subscribe 'annotationsLoaded', (annotations) =>
      for annotation in annotations
        this.anchor(annotation)

  _connectAnnotationUISync: (crossframe, config) ->
    crossframe.on 'focusAnnotations', (tags=[], className) =>
      for anchor in @anchors when anchor.highlights?
        toggle = anchor.annotation.$tag in tags
        $(anchor.highlights).toggleClass(className, toggle)


    crossframe.on 'scrollToAnnotation', (tag, className) =>
      for anchor in @anchors when anchor.highlights?
        if (anchor.annotation.$tag is tag)
          $(anchor.highlights).toggleClass(className) unless className is undefined

          # scroll to the feedback
          event = new CustomEvent('scrolltorange', {
            bubbles: true
            cancelable: true
            detail: anchor.range
          })
          defaultNotPrevented = @element[0].dispatchEvent(event)
          if defaultNotPrevented
            scrollIntoView(anchor.highlights[0])
        else
          # If the feedback is not selected and has one of the selected class, clear it.
          $(anchor.highlights).removeClass('annotator-hl-selected-public annotator-hl-selected-yours')

    crossframe.on 'getDocumentInfo', (cb) =>
      this.getDocumentInfo()
      .then((info) -> cb(null, info))
      .catch((reason) -> cb(reason))

    crossframe.on 'setVisibleHighlights', (state) =>
      # @visibleHighlights is false when the page is loaded. Then toggle it.
      @visibleHighlights = !@visibleHighlights
      this.setVisibleHighlights(@visibleHighlights)

    # crossframe.on 'showBucketList', (tags) =>
    #   for anchor in @anchors when anchor.highlights?
    #     toggle = anchor.annotation.$tag in tags
    #     $(anchor.highlights).toggleClass('annotator-hl-highlighted', toggle)
    #   # this.highlightAllselectedFeedback(anchor.highlights)

    #   # crossframe.on 'clickBucketBar', (tags) =>
    #   #   this.clickBucketBar(tags);

  destroy: ->
    $('#annotator-dynamic-style').remove()

    this.selections.unsubscribe()
    @adder.remove()

    @element.find('.annotator-hl').each ->
      $(this).contents().insertBefore(this)
      $(this).remove()

    @element.data('annotator', null)

    for name, plugin of @plugins
      @plugins[name].destroy()

    super

  anchor: (annotation, newAnnotation) ->
    self = this
    root = @element[0]

    # Anchors for all annotations are in the `anchors` instance property. These
    # are anchors for this annotation only. After all the targets have been
    # processed these will be appended to the list of anchors known to the
    # instance. Anchors hold an annotation, a target of that annotation, a
    # document range for that target and an Array of highlights.
    anchors = []

    # The targets that are already anchored. This function consults this to
    # determine which targets can be left alone.
    anchoredTargets = []

    # These are the highlights for existing anchors of this annotation with
    # targets that have since been removed from the annotation. These will
    # be removed by this function.
    deadHighlights = []

    # Initialize the target array.
    annotation.target ?= []

    locate = (target) ->
      # Check that the anchor has a TextQuoteSelector -- without a
      # TextQuoteSelector we have no basis on which to verify that we have
      # reanchored correctly and so we shouldn't even try.
      #
      # Returning an anchor without a range will result in this annotation being
      # treated as an orphan (assuming no other targets anchor).
      if not (target.selector ? []).some((s) => s.type == 'TextQuoteSelector')
        return Promise.resolve({annotation, target})

      # Find a target using the anchoring module.
      options = {
        cache: self.anchoringCache
        ignoreSelector: '[class^="annotator-"]'
      }
      return self.anchoring.anchor(root, target.selector, options)
      .then((range) -> {annotation, target, range})
      .catch(-> {annotation, target})

    highlight = (anchor) ->
      # Highlight the range for an anchor.
      return anchor unless anchor.range?
      return animationPromise ->
        range = xpathRange.sniff(anchor.range)
        normedRange = range.normalize(root)
        highlights = highlighter.highlightRange(normedRange, newAnnotation)

        $(highlights).data('annotation', anchor.annotation)
        anchor.highlights = highlights
        return anchor

    sync = (anchors) ->
      # Store the results of anchoring.

      # An annotation is considered to be an orphan if it has at least one
      # target with selectors, and all targets with selectors failed to anchor
      # (i.e. we didn't find it in the page and thus it has no range).
      hasAnchorableTargets = false
      hasAnchoredTargets = false
      for anchor in anchors
        if anchor.target.selector?
          hasAnchorableTargets = true
          if anchor.range?
            hasAnchoredTargets = true
            break
      annotation.$orphan = hasAnchorableTargets and not hasAnchoredTargets

      # Add the anchors for this annotation to instance storage.
      self.anchors = self.anchors.concat(anchors)

      # Let plugins know about the new information.
      self.plugins.BucketBar?.update()
      self.plugins.CrossFrame?.sync([annotation])

      return anchors

    # Remove all the anchors for this annotation from the instance storage.
    for anchor in self.anchors.splice(0, self.anchors.length)
      if anchor.annotation is annotation
        # Anchors are valid as long as they still have a range and their target
        # is still in the list of targets for this annotation.
        if anchor.range? and anchor.target in annotation.target
          anchors.push(anchor)
          anchoredTargets.push(anchor.target)
        else if anchor.highlights?
          # These highlights are no longer valid and should be removed.
          deadHighlights = deadHighlights.concat(anchor.highlights)
          delete anchor.highlights
          delete anchor.range
      else
        # These can be ignored, so push them back onto the new list.
        self.anchors.push(anchor)

    # Remove all the highlights that have no corresponding target anymore.
    raf -> highlighter.removeHighlights(deadHighlights)

    # Anchor any targets of this annotation that are not anchored already.
    for target in annotation.target when target not in anchoredTargets
      anchor = locate(target).then(highlight)
      anchors.push(anchor)

    return Promise.all(anchors).then(sync)

  detach: (annotation) ->
    anchors = []
    targets = []
    unhighlight = []

    for anchor in @anchors
      if anchor.annotation is annotation
        unhighlight.push(anchor.highlights ? [])
      else
        anchors.push(anchor)

    this.anchors = anchors

    unhighlight = Array::concat(unhighlight...)
    raf =>
      highlighter.removeHighlights(unhighlight)
      this.plugins.BucketBar?.update()

  createAnnotation: (annotation = {}) ->
    self = this
    root = @element[0]
    newAnnotation = true

    ranges = @selectedRanges ? []
    @selectedRanges = null

    getSelectors = (range) ->
      options = {
        cache: self.anchoringCache
        ignoreSelector: '[class^="annotator-"]'
      }
      # Returns an array of selectors for the passed range.
      return self.anchoring.describe(root, range, options)

    setDocumentInfo = (info) ->
      annotation.document = info.metadata
      annotation.uri = info.uri

    setTargets = ([info, selectors]) ->
      # `selectors` is an array of arrays: each item is an array of selectors
      # identifying a distinct target.
      source = info.uri
      annotation.target = ({source, selector} for selector in selectors)

    info = this.getDocumentInfo()
    selectors = Promise.all(ranges.map(getSelectors))

    metadata = info.then(setDocumentInfo)
    targets = Promise.all([info, selectors]).then(setTargets)

    targets.then(-> self.publish('beforeAnnotationCreated', [annotation]))
    targets.then(-> self.anchor(annotation, newAnnotation))

    @crossframe?.call('showSidebar') unless annotation.$highlight
    annotation

  createHighlight: ->
    return this.createAnnotation({$highlight: true})

  # Create a blank comment (AKA "page note")
  createComment: () ->
    annotation = {}
    self = this

    prepare = (info) ->
      annotation.document = info.metadata
      annotation.uri = info.uri
      annotation.target = [{source: info.uri}]

    this.getDocumentInfo()
      .then(prepare)
      .then(-> self.publish('beforeAnnotationCreated', [annotation]))

    annotation

  # Public: Deletes the annotation by removing the highlight from the DOM.
  # Publishes the 'annotationDeleted' event on completion.
  #
  # annotation - An annotation Object to delete.
  #
  # Returns deleted annotation.
  deleteAnnotation: (annotation) ->
    if annotation.highlights?
      for h in annotation.highlights when h.parentNode?
        $(h).replaceWith(h.childNodes)

    this.publish('annotationDeleted', [annotation])
    annotation

  showAnnotations: (annotations) ->
    tags = (a.$tag for a in annotations)
    @crossframe?.call('showAnnotations', tags)
    @crossframe?.call('showSidebar')

  toggleAnnotationSelection: (annotations) ->
    tags = (a.$tag for a in annotations)
    @crossframe?.call('toggleAnnotationSelection', tags)

  updateAnnotations: (annotations) ->
    tags = (a.$tag for a in annotations)
    @crossframe?.call('updateAnnotations', tags)

  focusAnnotations: (annotations) ->
    tags = (a.$tag for a in annotations)
    @crossframe?.call('focusAnnotations', tags)

  _onSelection: (range, config) ->
    selection = document.getSelection()
    isBackwards = rangeUtil.isSelectionBackwards(selection)
    focusRect = rangeUtil.selectionFocusRect(selection)
    if !focusRect
      # The selected range does not contain any text
      this._onClearSelection()
      return

    for div in config.FeedbackDivLimitation
      doc_content = $(div)[0]
      selectedTextParentStart = selection.anchorNode.parentElement
      selectedTextParentFinish = selection.focusNode.parentElement
      isFeedbackOnDoc = ($.contains(doc_content, selectedTextParentStart) && $.contains(doc_content, selectedTextParentFinish) )

      if !isFeedbackOnDoc
        # If the selected text is not on the doc
        this._onClearSelection()
        return

    @selectedRanges = [range]

    $('.annotator-toolbar .h-icon-note')
      .attr('title', 'New Annotation')
      .removeClass('h-icon-note')
      .addClass('h-icon-annotate');

    {left, top, arrowDirection} = this.adderCtrl.target(focusRect, isBackwards)
    this.adderCtrl.showAt(left, top, arrowDirection)

  _onClearSelection: () ->
    this.adderCtrl.hide()
    @selectedRanges = []

    $('.annotator-toolbar .h-icon-annotate')
      .attr('title', 'New Page Note')
      .removeClass('h-icon-annotate')
      .addClass('h-icon-note');

  selectAnnotations: (annotations, toggle) ->
    if toggle
      this.toggleAnnotationSelection annotations
    else
      this.showAnnotations annotations

  onElementClick: (event) ->
    if (this.enableClick && !@selectedTargets?.length)
      @crossframe?.call('hideSidebar')

  onElementTouchStart: (event) ->
    # Mobile browsers do not register click events on
    # elements without cursor: pointer. So instead of
    # adding that to every element, we can add the initial
    # touchstart event which is always registered to
    # make up for the lack of click support for all elements.
    if (this.enableClick && !@selectedTargets?.length)
      @crossframe?.call('hideSidebar')

  onHighlightMouseover: (event) ->
    return unless @visibleHighlights
    annotation = $(event.currentTarget).data('annotation')
    annotations = event.annotations ?= []
    annotations.push(annotation)

    # The innermost highlight will execute this.
    # The timeout gives time for the event to bubble, letting any overlapping
    # highlights have time to add their annotations to the list stored on the
    # event object.
    if event.target is event.currentTarget
      setTimeout => this.focusAnnotations(annotations)

  onHighlightMouseout: (event) ->
    return unless @visibleHighlights
    this.focusAnnotations []

  onHighlightClick: (event) ->
    return unless @visibleHighlights
    annotation = $(event.currentTarget).data('annotation')
    annotations = event.annotations ?= []
    annotations.push(annotation)
    #  Clear all highlights on the doc when user clicks on an highlight
    selectedClassNames = 'annotator-hl-selected-public annotator-hl-selected-yours'
    for anchor in @anchors when anchor.highlights?
      #  if the clicked feedback is not the selected one, remove the highlight
      if not (anchor.annotation.$tag is annotation.$tag)
        $(anchor.highlights).removeClass(selectedClassNames)

    # See the comment in onHighlightMouseover
    if event.target is event.currentTarget
      xor = (event.metaKey or event.ctrlKey)
      setTimeout => this.selectAnnotations(annotations, xor)

  # Pass true to show the highlights in the frame or false to disable.
  setVisibleHighlights: (shouldShowHighlights) ->
    this.toggleHighlightClass(shouldShowHighlights)

  toggleHighlightClass: (shouldShowHighlights) ->
    if shouldShowHighlights
      @element.addClass(SHOW_HIGHLIGHTS_CLASS)
    else
      @element.removeClass(SHOW_HIGHLIGHTS_CLASS)

    @visibleHighlights = shouldShowHighlights
