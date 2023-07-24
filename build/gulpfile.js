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
    .src(['../src/core/**/*', '../src/core/.lua/**/*'], { base: '../src/core' })
    .pipe(gulp.dest('./MakoBuild'));
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
    .src(['./MakoBuild/**/*.lua', './MakoBuild/.**/*.lua'], { base: './MakoBuild' })
    .pipe(luamin())
    .pipe(gulp.dest('./MakoBuild'));
});

gulp.task('build-mako', gulp.series('clean', 'copy-folders', 'minify-css', 'minify-js', 'luamin-folder'));