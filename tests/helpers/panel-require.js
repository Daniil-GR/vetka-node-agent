'use strict';

const path = require('node:path');
const { createRequire } = require('node:module');

const panelRequire = createRequire(path.resolve(__dirname, '../../panel/package.json'));

module.exports = {
  panelRequire
};
