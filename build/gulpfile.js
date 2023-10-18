const gulp = require('gulp');
const cleanCSS = require('gulp-clean-css');
const uglify = require('gulp-uglify');
const { rimraf } = require('rimraf');
const luamin = require('./plugins/gulp-luamin');
const fs = require('fs');
const zip = require('gulp-zip');

gulp.task('clean', async function (cb) {
  await rimraf('ZipBuild');
  return cb();
});

gulp.task('copy-core', function () {
  return gulp
    .src(['../src/core/**/*', '../src/core/.lua/**/*', '../src/core/.certificate/**/*'], { base: '../src/core' })
    .pipe(gulp.dest('./ZipBuild'));
});

gulp.task('copy-mako', function () {
  return gulp
    .src(['../src/mako/**/*', '../src/mako/.lua/**/*', '../src/mako/.certificate/**/*', '../src/mako/.config'], { base: '../src/mako' })
    .pipe(gulp.dest('./ZipBuild'));
});

gulp.task('copy-opcua', function () {
  return gulp
    .src(['../src/opcua/**/*'], { base: '../src/opcua' })
    .pipe(gulp.dest('./ZipBuild/.lua/opcua'));
});


// Including lua-protobuf and Sparkplug lib
gulp.task('copy-lua-protobuf', function (cb) {
  if (fs.existsSync('../../lua-protobuf/protoc.lua') 
    && fs.existsSync('../../lua-protobuf/serpent.lua')) {
    return gulp
      .src(['../../lua-protobuf/protoc.lua', '../../lua-protobuf/serpent.lua'], { base: '../../lua-protobuf' })
      .pipe(gulp.dest('./ZipBuild/.lua/'))
      .on('end', function () {
        return gulp
          .src(['../src/sparkplug/*'], { base: '../src/sparkplug' })
          .pipe(gulp.dest('./ZipBuild/.lua'));
      });
  }
  return cb();
});

gulp.task('copy-lua-lpeg', function (cb) {
  if (fs.existsSync('../../LPeg/re.lua') ) {
    return gulp
      .src(['../../LPeg/re.lua', '../../lua-protobuf/serpent.lua'], { base: '../../LPeg' })
      .pipe(gulp.dest('./ZipBuild/.lua/'))
  }
  return cb();
});

gulp.task('copy-xedge', function () {
  return gulp
    .src(['../src/xedge/**/*', '../src/xedge/.lua/**/*', '../src/xedge/.certificate/**/*', '../src/xedge/.config'], { base: '../src/xedge' })
    .pipe(gulp.dest('./ZipBuild'));
});

gulp.task('copy-acme', function () {
  return gulp
    .src(['../src/mako/.lua/acme/**/*'], { base: '../src/mako/.lua/acme' })
    .pipe(gulp.dest('./ZipBuild'));
});


gulp.task('minify-css', function () {
  return gulp
    .src(['./ZipBuild/**/*.css', './ZipBuild/.**/*.css'], { base: './ZipBuild' })
    .pipe(cleanCSS())
    .pipe(gulp.dest('./ZipBuild'));
});

gulp.task('minify-js', function () {
  return gulp
    .src(['./ZipBuild/**/*.js', './ZipBuild/.**/*.js'], { base: './ZipBuild' })
    .pipe(uglify())
    .pipe(gulp.dest('./ZipBuild'));
});

gulp.task('luamin-folder', function () {
  return gulp
    .src(['./ZipBuild/**/*.lua', './ZipBuild/.lua/**/*.lua'], { base: './ZipBuild' })
    .pipe(luamin())
    .pipe(gulp.dest('./ZipBuild'));
});

gulp.task('zip-mako', function (cb) {
  rimraf('mako.zip');
  return gulp
    .src(['./ZipBuild/**/*', './ZipBuild/.lua/**/*', './ZipBuild/.certificate/*'], { base: './ZipBuild' })
    .pipe(zip('mako.zip'))
    .pipe(gulp.dest('./'));
});

gulp.task('zip-Xedge', function (cb) {
  rimraf('Xedge.zip');
  return gulp
    .src(['./ZipBuild/**/*', './ZipBuild/.lua/**/*', './ZipBuild/.certificate/*'], { base: './ZipBuild' })
    .pipe(zip('Xedge.zip'))
    .pipe(gulp.dest('./'));
});

gulp.task('build-mako', 
  gulp.series(
    'clean',
    'copy-core',
    'copy-mako',
    'copy-opcua',
    'copy-lua-protobuf',
    'copy-lua-lpeg',
    'minify-css',
    'minify-js',
    'luamin-folder',
    'zip-mako',
    'clean',
     ));

gulp.task('build-xEdge', 
  gulp.series(
    'clean',
    'copy-core',
    'copy-xedge',
    'copy-opcua',
    'copy-lua-protobuf',
    'minify-css',
    'minify-js',
    'luamin-folder',
    'zip-mako',
    'clean',
     ));