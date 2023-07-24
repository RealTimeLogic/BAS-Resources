const gulp = require('gulp');
const cleanCSS = require('gulp-clean-css');
const uglify = require('gulp-uglify');
const { rimraf } = require('rimraf');
const luamin = require('./plugins/gulp-luamin');

gulp.task('clean', async function (cb) {
  await rimraf('dist');
  return cb();
});

gulp.task('copy-folders', function () {
  return gulp
    .src(['../src/core/**/*'])
    .pipe(gulp.dest('./Mako'));
});

gulp.task('copy-hidden-folders', function () {
  return gulp
    .src(['../src/core/.lua/**/*'])
    .pipe(gulp.dest('./Mako/.lua'));
});

gulp.task('minify-css', function () {
  return gulp
    .src(['./Mako/**/*.css', './Mako/.**/*.css'])
    .pipe(cleanCSS())
    .pipe(gulp.dest('./Mako/'));
});

gulp.task('minify-js', function () {
  return gulp
    .src(['./Mako/**/*.js', './Mako/.**/*.js'])
    .pipe(uglify())
    .pipe(gulp.dest('./Mako/'));
});

gulp.task('luamin-folder', function () {
  return gulp
    .src(['./Mako/**/*.lua', './Mako/.**/*.lua'])
    .pipe(luamin())
    .pipe(gulp.dest('./Mako/'));
});

gulp.task('build-mako', gulp.series('clean', 'copy-folders', 'copy-hidden-folders', 'minify-css', 'minify-js', 'luamin-folder'));