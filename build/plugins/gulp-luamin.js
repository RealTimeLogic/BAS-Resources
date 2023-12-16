/**
 * Created by Administrator on 2016/4/5.
 */

const through = require('through2');
const PluginError = require('plugin-error');
const luamin = require('./luamin.js');
const { Buffer } = require('buffer');

module.exports = function () {
	'use strict';
	
	return through.obj(function (file, encoding, callback) {
		if (file.isNull()) {
			this.push(file);
			return callback();
		}

		if (file.isStream()) {
			this.emit('error', new PluginError('gulp-luaminify', 'Streaming not supported'));
			return callback();
		}

		try {
			const fileString = file.contents.toString();
			file.contents = new Buffer.from(luamin.minify(fileString).toString());
		} catch (err) {
			this.emit('error', new PluginError('gulp-luaminify', err));
		}

		this.push(file);
		callback();
	});
};