
/*
   This gulpfile is used if the developer wants to test the code directly on the device.
   In other cases, just use the npm scripts.
*/

config = require("config")
gulp   = require('gulp')
Rsync  = require('rsync')
path   = require('path')
shell  = require('gulp-shell')

toWatch     = ['src/**/*.coffee', 'package.json', 'config/local.coffee']
outputDir   = path.join(__dirname, '/*')
deviceIP    = config.ip
dockerToken = config.docker.registry_auth.credentials.password
appName     = require(__dirname + '/package.json').name

remoteLocation = `root@${deviceIP}:/data/Dev/${appName}`

if (!dockerToken) {
  throw new Error('dockerToken is falsy!')
}

if (!deviceIP) {
  throw new Error('deviceIP is falsy!')
}

if (!config.key) {
  throw new Error(`No SSH key specified! Please run 'export IVH_SSH_KEY=<path_to_your_key>'`)
}


startCommand   = '/bin/bash -c "cd /Dev; NODE_ENV=dev_device nodemon src/main.coffee"'
installCommand = `/bin/bash -c "cd /Dev; rm -rf ${appName}; mkdir -p ${appName}; cd ${appName}; npm i --production"`
nodeCommand    = `docker run \
	--net host \
	-i \
	--rm \
	--name dev-${appName} \
	-e 'DEBUG=app:*' \
	-e 'DOCKER_REGISTRY_TOKEN=${dockerToken}' \
	-v /config/certs:/certs \
	-v /version:/version \
  -v /data/groups:/groups \
	-v /var/run/docker.sock:/var/run/docker.sock \
  -v /data/Dev/${appName}:/Dev \
  docker.viriciti.com/device/docker-node-dev`


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
  `scp -i ${config.key} ${__dirname}/package.json ${remoteLocation}/package.json`
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
