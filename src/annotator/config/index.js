'use strict';

var settingsFrom = require('./settings');

/**
 * Reads the Hypothesis configuration from the environment.
 *
 * @param {Window} window_ - The Window object to read config from.
 */
function configFrom(window_) {
  var settings = settingsFrom(window_);
  return {
    annotations: settings.annotations,
    // URL where client assets are served from. Used when injecting the client
    // into child iframes.
    assetRoot: settings.hostPageSetting('assetRoot', {allowInBrowserExt: true}),
    branding: settings.hostPageSetting('branding'),
    // URL of the client's boot script. Used when injecting the client into
    // child iframes.
    clientUrl: settings.clientUrl,
    enableExperimentalNewNoteButton: settings.hostPageSetting('enableExperimentalNewNoteButton'),
    theme: settings.hostPageSetting('theme'),
    usernameUrl: settings.hostPageSetting('usernameUrl'),
    onLayoutChange: settings.hostPageSetting('onLayoutChange'),
    openSidebar: settings.hostPageSetting('openSidebar', {allowInBrowserExt: true}),
    query: settings.query,
    services: settings.hostPageSetting('services'),
    showHighlights: settings.showHighlights,
    sidebarAppUrl: settings.sidebarAppUrl,
    // Subframe identifier given when a frame is being embedded into
    // by a top level client
    subFrameIdentifier: settings.hostPageSetting('subFrameIdentifier', {allowInBrowserExt: true}),
    // When onElementClick is false, clicking (or tabbing around on mobile)
    // outside of the elements on the guest page doesn't close the sidebar
    onElementClick: settings.hostPageSetting('onElementClick', {allowInBrowserExt: true}),
    isHighlightBtnVisible: settings.hostPageSetting('isHighlightBtnVisible', {allowInBrowserExt:true}),
    // The locale is going to come from cookies, this is a temporary solution.
    locale: settings.hostPageSetting('locale', {allowInBrowserExt:true}),
    injectSidebar: settings.hostPageSetting('injectSidebar', {allowInBrowserExt: true}),
    FeedbackDivLimitation: settings.hostPageSetting('FeedbackDivLimitation', {allowInBrowserExt: true}),
  };
}

module.exports = configFrom;
