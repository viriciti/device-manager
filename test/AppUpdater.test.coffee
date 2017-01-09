# (require "leaked-handles").set {
# 	fullStack: true
# 	timeout: 30000
# 	debugSockets: true
# }

test       = require "tape"
AppUpdater = require "../src/manager/AppUpdater"

updater = AppUpdater()

test "Creating the mixin from the device's groups ( > 1 group )", (t) ->
	deviceGroups =
		1: "default"
		2: "g3"
		3: "g2"

	groups =
		default:
			app1:
				containerName: "app1"
				fromImage: "image1:1.0.0"
				labels:
					group: "default"
					manual: false
			app2:
				containerName: "app2"
				fromImage: "image2:2.1.0"
				labels:
					group: "default"
					manual: false

			app6:
				containerName: "app6"
				fromImage: "image2:2.1.0"
				labels:
					group: "default"
					manual: false
		g2:
			app1:
				containerName: "app1"
				fromImage: "image1:1.0.0"
				labels:
					group: "g2"
					manual: false

		g3:
			app2:
				containerName: "app2"
				fromImage: "image2:3.1.0"
				labels:
					group: "g3"
					manual: false
			app5:
				containerName: "app5"
				fromImage: "image5:2.1.0"
				labels:
					group: "g3"
					manual: false

		g4:
			app2:
				containerName: "app2"
				fromImage: "image2:3.1.0"
				labels:
					group: "g3"
					manual: false
			app5:
				containerName: "app5"
				fromImage: "image5:2.1.0"
				labels:
					group: "g3"
					manual: false


	expectedAppsToInstall =
		app1:
			containerName: "app1"
			fromImage: "image1:1.0.0"
			labels:
				group: "g2"
				manual: false
		app2:
			containerName: "app2"
			fromImage: "image2:3.1.0"
			labels:
				group: "g3"
				manual: false
		app5:
			containerName: "app5"
			fromImage: "image5:2.1.0"
			labels:
				group: "g3"
				manual: false
		app6:
			containerName: "app6"
			fromImage: "image2:2.1.0"
			labels:
				group: "default"
				manual: false



	resultGroupsMixin = updater._createGroupsMixin groups, deviceGroups
	t.deepEqual resultGroupsMixin, expectedAppsToInstall,
		"The mixin should contain apps from both groups and when
			duplicates are present, get the app with the latest group"
	t.end()


test "Check if an already existing app from a group has a new image version", (t) ->
	appsToInstall =
		app1:
			containerName: "app1"
			fromImage: "image1:1.0.1"
			labels:
				group: "g2"
				manual: false

		app2:
			containerName: "app2"
			fromImage: "image2:2.3.0"
			labels:
				group: "g2"
				manual: false

	existingApp =
		app1:
			name: "app1"
			image: "image1:1.0.0"
			labels:
				group: "g2"
				manual: false

		app2:
			name: "app2"
			image: "image2:2.3.0"
			labels:
				group: "g2"
				manual: false

	isToUpdate = updater._hasOutdatedApps appsToInstall.app1, existingApp.app1
	t.ok isToUpdate
	isToUpdate = updater._hasOutdatedApps appsToInstall.app2, existingApp.app2
	t.notOk isToUpdate
	t.end()


test "Get apps to install, remove and skip from the device", (t) ->
	groupsMixin =
		app1:
			containerName: "app1"
			fromImage: "image1:1.0.0"
			labels:
				group: "g2"
				manual: false
		app2:
			containerName: "app2"
			fromImage: "image2:3.1.0"
			labels:
				group: "g3"
				manual: false
		app5:
			containerName: "app5"
			fromImage: "image5:2.1.0"
			labels:
				group: "g3"
				manual: false

		app6:
			containerName: "app6"
			fromImage: "image2:2.1.0"
			labels:
				group: "default"
				manual: false
		app7:
			containerName: "app7"
			fromImage: "image3:2.2.0"
			labels:
				group: "default"
				manual: false


	deviceCurrentApps =
		app6:
			name: "app6"
			image: "image2:2.1.0"
			labels:
				group: "default"
				manual: false

		app7:
			name: "app7"
			image: "image3:2.1.0"
			labels:
				group: "default"
				manual: false

		app5:
			name: "app5"
			image: "image5:2.1.0"
			labels:
				group: "g3"
				manual: false

		app2:
			name: "app2"
			image: "image2:3.1.0"
			labels:
				group: "g2"
				manual: false


	expectedAppsToChange =
		install: [
			{
				containerName: "app1"
				fromImage: "image1:1.0.0"
				labels:
					group: "g2"
					manual: false
			},
			{
				containerName: "app2"
				fromImage: "image2:3.1.0"
				labels:
					group: "g3"
					manual: false
			},
			{
				containerName: "app7"
				fromImage: "image3:2.2.0"
				labels:
					group: "default"
					manual: false
			},
		]
		remove: []
		skip: [ "app5", "app6" ]

	resultAppsToChange = updater._getAppsToChange groupsMixin, deviceCurrentApps
	t.deepEqual expectedAppsToChange, resultAppsToChange
	t.end()


test "Get apps to install, remove and skip when a configuration changes", (t) ->
	groupsMixin =
		app6:
			containerName: "app6"
			fromImage: "image2:2.1.0"
			environment: [ "NODE_ENV=production" ]
			privileged: false
			networkMode: "host"
			restartPolicy: "always"
			mounts: {}
			ports: {}
			labels:
				group: "default"
				manual: false
		app7:
			containerName: "app7"
			fromImage: "image3:2.2.0"
			environment: [ "NODE_ENV=development" ]
			privileged: true
			networkMode: "host"
			restartPolicy: "always"
			mounts: {}
			ports: {}
			labels:
				group: "default"
				manual: false

	deviceCurrentApps =
		app6:
			name: "app6"
			image: "image2:2.1.0"
			environment: [ "NODE_ENV=development" ]
			privileged: true
			networkMode: "host"
			restartPolicy:
				type: "always"
			mounts: {}
			ports: {}
			labels:
				group: "default"
				manual: false
		app7:
			name: "app7"
			image: "image3:2.2.0"
			environment: [ "NODE_ENV=development" ]
			privileged: true
			networkMode: "host"
			restartPolicy:
				type: "always"
			mounts: {}
			ports: {}
			labels:
				group: "default"
				manual: false


	expectedAppsToChange =
		install: [
			{
				containerName: "app6"
				fromImage: "image2:2.1.0"
				environment: [ "NODE_ENV=production" ]
				privileged: false
				networkMode: "host"
				restartPolicy: "always"
				mounts: {}
				ports: {}
				labels:
					group: "default"
					manual: false
			}
		]
		remove: []
		skip: [ "app7" ]

	resultAppsToChange = updater._getAppsToChange groupsMixin, deviceCurrentApps
	t.deepEqual expectedAppsToChange, resultAppsToChange
	t.end()

test "Get apps to install, remove and skip when there's nothing to change", (t) ->
	groupsMixin =
		app6:
			containerName: "app6"
			fromImage: "image2:2.1.0"
			labels:
				group: "default"
				manual: false
		app7:
			containerName: "app7"
			fromImage: "image3:2.2.0"
			labels:
				group: "default"
				manual: false


	deviceCurrentApps =
		app6:
			name: "app6"
			image: "image2:2.1.0"
			labels:
				group: "default"
				manual: false
		app7:
			name: "app7"
			image: "image3:2.2.0"
			labels:
				group: "default"
				manual: false


	expectedAppsToChange =
		install: []
		remove: []
		skip: [ "app6", "app7" ]

	resultAppsToChange = updater._getAppsToChange groupsMixin, deviceCurrentApps
	t.deepEqual expectedAppsToChange, resultAppsToChange
	t.end()


test "Get apps to install, remove and skip when there are manual installed apps", (t) ->
	groupsMixin =
		app6:
			containerName: "app6"
			fromImage: "image2:2.1.0"
			labels:
				group: "default"
				manual: false
		app7:
			containerName: "app7"
			fromImage: "image3:2.2.0"
			labels:
				group: "default"
				manual: false


	deviceCurrentApps =
		app6:
			name: "app6"
			image: "image2:2.1.0"
			labels:
				group: "default"
				manual: false
		app7:
			name: "app7"
			image: "image3:2.2.0"
			labels:
				group: "default"
				manual: false
		app8:
			name: "app8"
			image: "image3:9.2.0"
			labels: {}


	expectedAppsToChange =
		install: []
		remove: []
		skip: [ "app8", "app6", "app7" ]

	resultAppsToChange = updater._getAppsToChange groupsMixin, deviceCurrentApps
	t.deepEqual expectedAppsToChange, resultAppsToChange
	t.end()

test "Get apps to install, remove and skip when apps are removed from a group", (t) ->
	groupsMixin =
		app7:
			containerName: "app7"
			fromImage: "image3:2.2.0"
			labels:
				group: "default"
				manual: false


	deviceCurrentApps =
		app6:
			name: "app6"
			image: "image2:2.1.0"
			labels:
				group: "default"
				manual: false
		app7:
			name: "app7"
			image: "image3:2.2.0"
			labels:
				group: "default"
				manual: false
		app8:
			name: "app8"
			image: "image3:9.2.0"
			labels: {}


	expectedAppsToChange =
		install: []
		remove: [ "app6" ]
		skip: [ "app8", "app7" ]

	resultAppsToChange = updater._getAppsToChange groupsMixin, deviceCurrentApps
	t.deepEqual resultAppsToChange, expectedAppsToChange
	t.end()

test "Updating the Docker status", (t) ->
	t.comment "Test groups when size is 1 and groups is not default"
	groups =
		somegroup:
			app1:
				containerName: "app1"
				fromImage: "image1:1.0.0"
				labels:
					group: "somegroup"
					manual: false
			app2:
				containerName: "app2"
				fromImage: "image2:3.1.0"
				labels:
					group: "somegroup"
					manual: false

	deviceGroups = []

	updater.update groups, deviceGroups, (error) ->
		t.equal error.message, "Size group is 1, but the group is not default"
		t.end()
