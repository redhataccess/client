extend = require('extend')
raf = require('raf')
Hammer = require('hammerjs')
$ = require('jquery')

Host = require('./host')
annotationCounts = require('./annotation-counts')
sidebarTrigger = require('./sidebar-trigger')
events = require('../shared/bridge-events')
features = require('./features')

# Minimum width to which the frame can be resized.
MIN_RESIZE = 280


module.exports = class Sidebar extends Host
  options:
    Document: {}
    TextSelection: {}
    BucketBar:
      container: '.annotator-frame'
    Toolbar:
      container: '.annotator-frame'

  renderFrame: null
  gestureState: null

  constructor: (element, config) ->
    super
    this.hide()

    if config.openSidebar || config.annotations || config.query
      this.on 'panelReady', => this.show()

    if @plugins.BucketBar?
      @plugins.BucketBar.element.on 'mouseup', (event) => this.showBucketList()

    if @plugins.Toolbar?
      @toolbarWidth = @plugins.Toolbar.getWidth()
      if config.theme == 'clean'
        @plugins.Toolbar.disableMinimizeBtn()
        @plugins.Toolbar.disableHighlightsBtn()
        @plugins.Toolbar.disableNewNoteBtn()
      else if config.theme == 'custom'
        @plugins.Toolbar.disableHighlightsBtn()
        @plugins.Toolbar.disableNewNoteBtn()
        @plugins.Toolbar.disableCloseBtn()
      else
        @plugins.Toolbar.disableCloseBtn()

      this._setupGestures()

    # The partner-provided callback functions.
    serviceConfig = config.services?[0]
    if serviceConfig
      @onLoginRequest = serviceConfig.onLoginRequest
      @onLogoutRequest = serviceConfig.onLogoutRequest
      @onSignupRequest = serviceConfig.onSignupRequest
      @onProfileRequest = serviceConfig.onProfileRequest
      @onHelpRequest = serviceConfig.onHelpRequest

    @onLayoutChange = config.onLayoutChange

    # initial layout notification
    this._notifyOfLayoutChange(false)

    this._setupSidebarEvents()

  _setupSidebarEvents: ->
    annotationCounts(document.body, @crossframe)
    sidebarTrigger(document.body, => this.show())
    features.init(@crossframe)

    @crossframe.on('showSidebar', => this.show())
    @crossframe.on('hideSidebar', => this.hide())
    @crossframe.on(events.LOGIN_REQUESTED, =>
      if @onLoginRequest
        @onLoginRequest()
    )
    @crossframe.on(events.LOGOUT_REQUESTED, =>
      if @onLogoutRequest
        @onLogoutRequest()
    )
    @crossframe.on(events.SIGNUP_REQUESTED, =>
      if @onSignupRequest
        @onSignupRequest()
    )
    @crossframe.on(events.PROFILE_REQUESTED, =>
      if @onProfileRequest
        @onProfileRequest()
    )
    @crossframe.on(events.HELP_REQUESTED, =>
      if @onHelpRequest
        @onHelpRequest()
    )
    # Return this for chaining
    this

  _setupGestures: ->
    $toggle = @toolbar.find('[name=sidebar-toggle]')

    if $toggle[0]
      # Prevent any default gestures on the handle
      $toggle.on('touchmove', (event) -> event.preventDefault())

      # Set up the Hammer instance and handlers
      mgr = new Hammer.Manager($toggle[0])
      .on('panstart panend panleft panright', this.onPan)
      .on('swipeleft swiperight', this.onSwipe)

      # Set up the gesture recognition
      pan = mgr.add(new Hammer.Pan({direction: Hammer.DIRECTION_HORIZONTAL}))
      swipe = mgr.add(new Hammer.Swipe({direction: Hammer.DIRECTION_HORIZONTAL}))
      swipe.recognizeWith(pan)

      # Set up the initial state
      this._initializeGestureState()

      # Return this for chaining
      this

  _initializeGestureState: ->
    @gestureState =
      initial: null
      final: null

  # Schedule any changes needed to update the sidebar layout.
  _updateLayout: ->
    # Only schedule one frame at a time
    return if @renderFrame

    # Schedule a frame
    @renderFrame = raf =>
      @renderFrame = null  # Clear the schedule

      # Process the resize gesture
      if @gestureState.final isnt @gestureState.initial
        m = @gestureState.final
        w = -m
        @frame.css('margin-left', "#{m}px")
        if w >= MIN_RESIZE then @frame.css('width', "#{w}px")
        this._notifyOfLayoutChange()

  ###*
  # Notify integrator when sidebar layout changes via `onLayoutChange` callback.
  #
  # @param [boolean] explicitExpandedState - `true` or `false` if the sidebar
  #   is being directly opened or closed, as opposed to being resized via
  #   the sidebar's drag handles.
  ###
  _notifyOfLayoutChange: (explicitExpandedState) =>
    toolbarWidth = @toolbarWidth || 0

    # The sidebar structure is:
    #
    # [ Toolbar    ][                                   ]
    # [ ---------- ][ Sidebar iframe container (@frame) ]
    # [ Bucket Bar ][                                   ]
    #
    # The sidebar iframe is hidden or shown by adjusting the left margin of its
    # container.

    if @onLayoutChange
      rect = @frame[0].getBoundingClientRect()
      computedStyle = window.getComputedStyle(@frame[0])
      width = parseInt(computedStyle.width)
      leftMargin = parseInt(computedStyle.marginLeft)

      # The width of the sidebar that is visible on screen, including the
      # toolbar, which is always visible.
      frameVisibleWidth = toolbarWidth

      if explicitExpandedState?
        # When we are explicitly saying to open or close, jump
        # straight to the upper and lower bounding widths.
        if explicitExpandedState
          frameVisibleWidth += width
      else
        if leftMargin < MIN_RESIZE
          # When the width hits its threshold of MIN_RESIZE,
          # the left margin continues to push the sidebar off screen.
          # So it's the best indicator of width when we get below that threshold.
          # Note: when we hit the right edge, it will be -0
          frameVisibleWidth += -leftMargin
        else
          frameVisibleWidth += width

      # Since we have added logic on if this is an explicit show/hide
      # and applied proper width to the visible value above, we can infer
      # expanded state on that width value vs the lower bound
      expanded = frameVisibleWidth > toolbarWidth

      @onLayoutChange({
        expanded: expanded,
        width: if expanded then frameVisibleWidth else toolbarWidth,
        height: rect.height,
      })

  onPan: (event) =>
    switch event.type
      when 'panstart'
        # Initialize the gesture state
        this._initializeGestureState()
        # Immadiate response
        @frame.addClass 'annotator-no-transition'
        # Escape iframe capture
        @frame.css('pointer-events', 'none')
        # Set origin margin
        @gestureState.initial = parseInt(getComputedStyle(@frame[0]).marginLeft)

      when 'panend'
        # Re-enable transitions
        @frame.removeClass 'annotator-no-transition'
        # Re-enable iframe events
        @frame.css('pointer-events', '')
        # Snap open or closed
        if @gestureState.final <= -MIN_RESIZE
          this.show()
        else
          this.hide()
        # Reset the gesture state
        this._initializeGestureState()

      when 'panleft', 'panright'
        return unless @gestureState.initial?
        # Compute new margin from delta and initial conditions
        m = @gestureState.initial
        d = event.deltaX
        @gestureState.final = Math.min(Math.round(m + d), 0)
        # Start updating
        this._updateLayout()

  onSwipe: (event) =>
    switch event.type
      when 'swipeleft'
        this.show()
      when 'swiperight'
        this.hide()

  show: ->
    # It is only for analitics
    @crossframe.call('sidebarOpened')

    # Making the feedback button disabled and iframe enabled.
    @toolbar = @frame.find('.annotator-toolbar')
    @toolbar.css 'display': 'none'
    @feedbackpanel = @frame.find('[name=hyp_sidebar_frame]')
    @feedbackpanel.css 'display': ''
    # Close the table content when sidebar is open
    @tocToggleS = $('.toc-toggle.toc-show');
    @tocToggleS.addClass('collapsed')
    @tocMain = $('.toc-main')
    @tocMain.removeClass('in')

    # The original code from Hypothesis. They changes the margin to make it enabled/disabled
    # @frame.css 'margin-left': "#{-1 * @frame.width()}px"
    # @frame.removeClass 'annotator-collapsed'
    # if @plugins.Toolbar?
    #   @plugins.Toolbar.showCollapseSidebarBtn();
    #   @plugins.Toolbar.showCloseBtn();

    # This piece of code enables the BucketBar when toggled. It is commented out now,
    # Because BucketBar is going to be hidden in phase 1.
    # if @plugins.BucketBar?
    #   @plugins.BucketBar.showBucketBar();

    # if @options.showHighlights == 'whenSidebarOpen'
      # @setVisibleHighlights(false)

    this._notifyOfLayoutChange(true)

  hide: ->
    @toolbar = @frame.find('.annotator-toolbar')
    @toolbar.css 'display': ''
    @feedbackpanel = @frame.find('[name=hyp_sidebar_frame]')
    @feedbackpanel.css 'display': 'none'
    # Clear existing highlights
    @setVisibleHighlights(false)
    # Clear any selected text on the doc
    allFeedbackOnThePage = document.querySelectorAll('.annotator-hl-selected-public, .annotator-hl-selected-yours');
    for feedback in allFeedbackOnThePage
      feedback.classList.remove('annotator-hl-selected-public', 'annotator-hl-selected-yours');
    # Manages the visibility of sidebar and table content on the page
    @tocToggleS = $('.toc-toggle.toc-show');
    #  if it is already collapsed don't do anything; if not, open the table content when sidebar is closed
    isAlreadyCollapsed = @tocToggleS.hasClass('collapsed')
    if not isAlreadyCollapsed
      @tocToggleS.removeClass('collapsed')
      @tocMain = $('.toc-main')
      @tocMain.addClass('in')

    # The original code from Hypothesis. They changes the margin to make it enabled/disabled
    # @frame.css 'margin-left': ''
    # @frame.addClass 'annotator-collapsed'
    # @plugins.Toolbar.hideCloseBtn();
    # if @plugins.Toolbar?
    #   @plugins.Toolbar.showExpandSidebarBtn();
    # This piece of code disables the BucketBar when toggled. It is commented out now,
    # Because BucketBar is going to be hidden in phase 1.
    # if @plugins.BucketBar?
    #   @plugins.BucketBar.hideBucketBar();

    # if @options.showHighlights == 'whenSidebarOpen'
    #   @setVisibleHighlights(false)

    this._notifyOfLayoutChange(false)

  isOpen: ->
    !@frame.hasClass('annotator-collapsed')

  setAllVisibleHighlights: (shouldShowHighlights) ->
    @crossframe.call('setVisibleHighlights', shouldShowHighlights)

    # Let the Toolbar know about this event
    this.publish 'setVisibleHighlights', shouldShowHighlights

  showBucketList: ->
    [tabs,buckets] = [@plugins.BucketBar.tabs, @plugins.BucketBar.buckets]
    index = if $(event.target)[0].className.includes('annotator-bucket-indicator') then $(event.target) else $(event.target).parent()
    bucket = tabs.index(index)
    [tags, annotations] = [[], []]
    for anchor in buckets[bucket]
      tags.push(anchor.annotation.$tag)
    event.stopPropagation()
    @crossframe?.call('showBucketList', tags);
