const gulp = require('gulp');
const cleanCSS = require('gulp-clean-css');
const uglify = require('gulp-uglify');
const { rimraf } = require('rimraf');
const luamin = require('./plugins/gulp-luamin');
const fs = require('fs');

gulp.task('clean', async function (cb) {
  await rimraf('MakoBuild');
  return cb();
});

gulp.task('copy-core', function () {
  return gulp
    .src(['../src/core/**/*', '../src/core/.lua/**/*', '../src/core/.certificate/**/*'], { base: '../src/core' })
    .pipe(gulp.dest('./MakoBuild'));
});

gulp.task('copy-mako', function () {
  return gulp
    .src(['../src/mako/**/*', '../src/mako/.lua/**/*', '../src/mako/.certificate/**/*', '../src/mako/.config'], { base: '../src/mako' })
    .pipe(gulp.dest('./MakoBuild'));
});

gulp.task('copy-opcua', function () {
  return gulp
    .src(['../src/opcua/**/*'], { base: '../src/opcua' })
    .pipe(gulp.dest('./MakoBuild/.lua/opcua'));
});


// Including lua-protobuf and Sparkplug lib
gulp.task('copy-lua-protobuf', function (cb) {
  if (fs.existsSync('../../lua-protobuf/protoc.lua') 
    && fs.existsSync('../../lua-protobuf/serpent.lua')) {
    return gulp
      .src(['../../lua-protobuf/protoc.lua', '../../lua-protobuf/serpent.lua'], { base: '../../lua-protobuf' })
      .pipe(gulp.dest('./MakoBuild/.lua/'))
      .on('end', function () {
        return gulp
          .src(['../src/sparkplug/*'], { base: '../src/sparkplug' })
          .pipe(gulp.dest('./MakoBuild/.lua'));
      });
  }
  return cb();
});

gulp.task('minify-css', function () {
  return gulp
    .src(['./MakoBuild/**/*.css', './MakoBuild/.**/*.css'], { base: './MakoBuild' })
    .pipe(cleanCSS())
    .pipe(gulp.dest('./MakoBuild'));
});

gulp.task('minify-js', function () {
  return gulp
    .src(['./MakoBuild/**/*.js', './MakoBuild/.**/*.js'], { base: './MakoBuild' })
    .pipe(uglify())
    .pipe(gulp.dest('./MakoBuild'));
});

gulp.task('luamin-folder', function () {
  return gulp
    .src(['./MakoBuild/**/*.lua', './MakoBuild/.lua/**/*.lua'], { base: './MakoBuild' })
    .pipe(luamin())
    .pipe(gulp.dest('./MakoBuild'));
});

gulp.task('build-mako', gulp.series('clean', 'copy-core', 'copy-mako', 'copy-opcua', 'copy-lua-protobuf', 'minify-css', 'minify-js', 'luamin-folder'));