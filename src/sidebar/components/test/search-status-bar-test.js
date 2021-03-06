'use strict';

var angular = require('angular');

var util = require('../../directive/test/util');

describe('searchStatusBar', function () {
  before(function () {
    angular.module('app', ['pascalprecht.translate'], function($translateProvider){
      $translateProvider.translations('en', {
        'Feedback' : 'Feedback',
      });
      $translateProvider.preferredLanguage('en');

    })
      .component('searchStatusBar', require('../search-status-bar'));
  });

  beforeEach(function () {
    angular.mock.module('app');
  });

  context('when there is a filter', function () {
    it('should display the filter count', function () {
      var elem = util.createDirective(document, 'searchStatusBar', {
        filterActive: true,
        filterMatchCount: 5,
      });
      assert.include(elem[0].textContent, '5 search results');
    });
  });

  context('when there is a selection', function () {
    it('should display the "Show all feedback (2)" message when there are 2 annotations', function () {
      var msg = 'Show all feedback';
      var msgCount = '(2)';
      var elem = util.createDirective(document, 'searchStatusBar', {
        selectionCount: 1,
        totalAnnotations: 2,
        selectedTab: 'annotation',
      });
      var clearBtn = elem[0].querySelector('button');
      assert.include(clearBtn.textContent, msg);
      assert.include(clearBtn.textContent, msgCount);
    });

    it('should display the "Show all notes (3)" message when there are 3 notes', function () {
      var msg = 'Show all notes';
      var msgCount = '(3)';
      var elem = util.createDirective(document, 'searchStatusBar', {
        selectionCount: 1,
        totalNotes: 3,
        selectedTab: 'note',
      });
      var clearBtn = elem[0].querySelector('button');
      assert.include(clearBtn.textContent, msg);
      assert.include(clearBtn.textContent, msgCount);
    });
  });
});
