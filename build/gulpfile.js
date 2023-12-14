const gulp = require('gulp');
const cleanCSS = require('gulp-clean-css');
const uglify = require('gulp-uglify');
const luamin = require('./plugins/gulp-luamin');

gulp.task('mako-minify-css', function () {
  return gulp
    .src(['./MakoBuild/**/*.css', './MakoBuild/.**/*.css'], { base: './MakoBuild' })
    .pipe(cleanCSS())
    .pipe(gulp.dest('./MakoBuild'));
});

gulp.task('mako-minify-js', function () {
  return gulp
    .src(['./MakoBuild/**/*.js', './MakoBuild/.**/*.js'], { base: './MakoBuild' })
    .pipe(uglify())
    .pipe(gulp.dest('./MakoBuild'));
});

gulp.task('mako-luamin-folder', function () {
  return gulp
    .src(['./MakoBuild/**/*.lua', './MakoBuild/.lua/**/*.lua'], { base: './MakoBuild' })
    .pipe(luamin())
    .pipe(gulp.dest('./MakoBuild'));
});

gulp.task('xedge-minify-css', function () {
  return gulp
    .src(['./XedgeBuild/**/*.css', './XedgeBuild/.**/*.css'], { base: './XedgeBuild' })
    .pipe(cleanCSS())
    .pipe(gulp.dest('./XedgeBuild'));
});

gulp.task('xedge-minify-js', function () {
  return gulp
    .src(['./XedgeBuild/**/*.js', './XedgeBuild/.**/*.js'], { base: './XedgeBuild' })
    .pipe(uglify())
    .pipe(gulp.dest('./XedgeBuild'));
});

gulp.task('xedge-luamin-folder', function () {
  return gulp
    .src(['./XedgeBuild/**/*.lua', './XedgeBuild/.lua/**/*.lua'], { base: './XedgeBuild' })
    .pipe(luamin())
    .pipe(gulp.dest('./XedgeBuild'));
});

gulp.task('minify-mako', 
  gulp.series(
    'mako-minify-css',
    'mako-minify-js',
    'mako-luamin-folder',
     ));
gulp.task('minify-xedge', 
  gulp.series(
    'xedge-minify-css',
    'xedge-minify-js',
    'xedge-luamin-folder',
     ));