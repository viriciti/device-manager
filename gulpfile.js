
/*
   This gulpfile is used if the developer wants to test the code directly on the device.
   In other cases, just use the npm scripts.
*/

config = require("config")
gulp = require('gulp')
Rsync = require('rsync')
path = require('path')
shell = require('gulp-shell')

toWatch = ['src/**/*.coffee', 'package.json', 'config/local.coffee']
outputDir = path.join(__dirname, '/*')
deviceIP = config.ip

remoteLocation = `root@${deviceIP}:/data/Dev/device-manager`

startCommand   = '/bin/bash -c "cd /Dev; NODE_ENV=dev_device nodemon src/main.coffee"'
installCommand = '/bin/bash -c "cd /Dev; npm i --production"'
nodeCommand    = 'docker run \
	--net host \
	-i \
	--rm \
	--name dev \
	-e \'DEBUG=app:*\' \
	-v /config/certs:/certs \
	-v /version:/version \
  -v /data/groups:/groups \
	-v /var/run/docker.sock:/var/run/docker.sock \
  -v /data/Dev/device-manager:/Dev \
  docker.viriciti.com/device/docker-node-dev'

if (!deviceIP) {
  throw new Error("deviceIP is falsy!")
}

gulp.task('sync', function () {

	rsync = new Rsync()
		.flags('rtvu')
		.source(outputDir)
		.destination(remoteLocation)
		.set('delete')
		.set('exclude-from', path.resolve(__dirname, 'sync_excludes'))
		.set('progress')

	return rsync.execute(function (error, code, cmd) {
		if (error) {
			console.log(error)
		}
	})
})

gulp.task('compile', shell.task([
	"npm run build-backend"
]))

gulp.task('send-package', shell.task([
  `scp -i ${config.key} ${__dirname}/package.json ${remoteLocation}`
]))

gulp.task('cmd', shell.task([
  `ssh -i ${config.key} root@${deviceIP}`
]))

gulp.task('start', shell.task([
	`ssh -i ${config.key} root@${deviceIP} '${nodeCommand} ${startCommand}'`
]))

gulp.task('install-task', shell.task([
	`ssh -i ${config.key} root@${deviceIP} '${nodeCommand} ${installCommand}'`
]))

gulp.task('watch', function () {
	gulp.watch(toWatch, ['sync'])
})

gulp.task('install', [ 'send-package', 'install-task' ])
gulp.task('default', [ 'watch', 'sync', 'start' ])
