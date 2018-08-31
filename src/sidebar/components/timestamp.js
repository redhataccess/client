'use strict';

var dateUtil = require('../date-util');

// @ngInject
function TimestampController($scope, time) {

  // A fuzzy, relative (eg. '6 days ago') format of the timestamp.
  this.relativeTimestamp = null;

  // A formatted version of the timestamp (eg. 'Tue 22nd Dec 2015, 16:00')
  this.absoluteTimestamp = '';

  var cancelTimestampRefresh;
  var self = this;

  function updateTimestamp() {
    //  This is (should be) a temporary solution.
    var modifiedTime = self.timestamp.replace(/ /g,'T').concat('Z');
    /* The 'updated' and 'created' data are sent to server in a format of (YYYY-MM-DDTMM:SS:SS.SSZ)
    * However, somehow it is returned in a format of (YYYY-MM-DD MM:SS:SS.SS) (No T and Z) and this causes
    * a format problem in Safari and incorrect information for updated and created attribute of an annotaion.
    */

    self.relativeTimestamp = time.toFuzzyString(modifiedTime);
    self.absoluteTimestamp = dateUtil.format(new Date(modifiedTime));

    if (self.timestamp) {
      if (cancelTimestampRefresh) {
        cancelTimestampRefresh();
      }
      cancelTimestampRefresh = time.decayingInterval(modifiedTime, function () {
        updateTimestamp();
        $scope.$digest();
      });
    }
  }

  this.$onChanges = function (changes) {
    if (changes.timestamp) {
      updateTimestamp();
    }
  };

  this.$onDestroy = function () {
    if (cancelTimestampRefresh) {
      cancelTimestampRefresh();
    }
  };
}

module.exports = {
  controller: TimestampController,
  controllerAs: 'vm',
  bindings: {
    className: '<',
    href: '<',
    timestamp: '<',
  },
  template: require('../templates/timestamp.html'),
};
