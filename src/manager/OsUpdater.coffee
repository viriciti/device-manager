config = require "config"
debug  = (require "debug") "app:app-updater"

log = (require "../lib/Logger") "OS Updater"

{ updateDevicesOs } = (require "../actions/osActions")()

module.exports = (mqttSocket) ->

    _handleVersion = (version) ->
        updateDevicesOs version, (error) ->
            return log.error error.message if error
            log.info "Device updated to version #{version}"

    return {
        init: ->
            { mqttTopic } = config.osUpdater

            mqttSocket.on "enabledOsVersion", _handleVersion

            mqttSocket.customSubscribe
                topic: mqttTopic
                opts:
                    qos: 2

            , (error) ->
                log.error "An error occured subscribing to the topic #{mqttTopic}: #{error.message}" if error


        clean: ->
            mqttSocket.removeListener "enabledOsVersion", _handleVersion
    }