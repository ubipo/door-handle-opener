import webserver
import string


LIMIT_SWITCH_TOUCHING = 0
TOP_LIMIT_PIN = 4
BOTTOM_LIMIT_PIN = 16
MOTOR_RELAY_A_PIN = 33
MOTOR_RELAY_B_PIN = 25
MOTOR_RELAY_ENABLE_PIN = 26
VIRTUAL_RELAY_NUMBER = 1
SPOOLING_LIMIT_CHECK_INTERVAL = 50
# Braking immediately after reaching the top limit switch leaves too much
# tension on the string
TOP_FREE_SPIN_TIME = 200
# But free spinning for too long will leave too much slack, risking the string
# getting loose from the spool. So we first free spin for a short time, and then
# brake.
TOP_BRAKING_TIME = 500
BOTTOM_BRAKING_TIME = 500


class DoorHandleOpener
  var state

  def init()
    self.state = "idle"
  end

  def setup()
    gpio.pin_mode(TOP_LIMIT_PIN, gpio.INPUT)
    gpio.pin_mode(BOTTOM_LIMIT_PIN, gpio.INPUT)
    gpio.pin_mode(MOTOR_RELAY_A_PIN, gpio.OUTPUT)
    gpio.pin_mode(MOTOR_RELAY_B_PIN, gpio.OUTPUT)
    gpio.pin_mode(MOTOR_RELAY_ENABLE_PIN, gpio.OUTPUT)
    self._turnOffVirtualRelay()
    self._spoolFreeSpin()
    tasmota.add_driver(self)
    tasmota.add_rule(
      [string.format("Power%d#state=1", VIRTUAL_RELAY_NUMBER)],  
      /-> self._handeVirtualRelayOn()
    )
  end

  def openDoorHandle()
    if self.state != "idle"
      return
    end
    self._spoolDown()
    self.state = "spooling_down"
    self._handleState()
  end

  def web_add_main_button()
    webserver.content_send("<p></p><button onclick='la(\"&m_door_handle_open=1\");'>Open door handle</button>")
  end

  def web_sensor()
    if webserver.has_arg("m_door_handle_open")
      self.openDoorHandle()
    end
  end

  def _turnOffVirtualRelay()
    tasmota.cmd(string.format("Power%d 0", VIRTUAL_RELAY_NUMBER), "0")
  end

  def _handeVirtualRelayOn()
    self._turnOffVirtualRelay()
    self.openDoorHandle()
  end

  def _spoolDown()
    gpio.digital_write(MOTOR_RELAY_A_PIN, gpio.HIGH)
    gpio.digital_write(MOTOR_RELAY_B_PIN, gpio.LOW)
    gpio.digital_write(MOTOR_RELAY_ENABLE_PIN, gpio.HIGH)
  end

  def _spoolUp()
    gpio.digital_write(MOTOR_RELAY_A_PIN, gpio.LOW)
    gpio.digital_write(MOTOR_RELAY_B_PIN, gpio.HIGH)
    gpio.digital_write(MOTOR_RELAY_ENABLE_PIN, gpio.HIGH)
  end

  def _spoolBrake()
    gpio.digital_write(MOTOR_RELAY_A_PIN, gpio.LOW)
    gpio.digital_write(MOTOR_RELAY_B_PIN, gpio.LOW)
    gpio.digital_write(MOTOR_RELAY_ENABLE_PIN, gpio.HIGH)
  end

  def _spoolFreeSpin()
    gpio.digital_write(MOTOR_RELAY_A_PIN, gpio.LOW)
    gpio.digital_write(MOTOR_RELAY_B_PIN, gpio.LOW)
    gpio.digital_write(MOTOR_RELAY_ENABLE_PIN, gpio.LOW)
  end

  def _handleState()
    if self.state == "spooling_down"
      if gpio.digital_read(TOP_LIMIT_PIN) == LIMIT_SWITCH_TOUCHING
        self._spoolBrake()
        self.state = "bottom_braking"
        tasmota.set_timer(BOTTOM_BRAKING_TIME, /-> self._handleState())
      else
        tasmota.set_timer(SPOOLING_LIMIT_CHECK_INTERVAL, /-> self._handleState())
      end
    elif self.state == "bottom_braking"
      self._spoolUp()
      self.state = "spooling_up"
      tasmota.set_timer(SPOOLING_LIMIT_CHECK_INTERVAL, /-> self._handleState())
    elif self.state == "spooling_up"
      if gpio.digital_read(BOTTOM_LIMIT_PIN) == LIMIT_SWITCH_TOUCHING
        self._spoolFreeSpin()
        self.state = "top_free_spin"
        tasmota.set_timer(TOP_FREE_SPIN_TIME, /-> self._handleState())
      else
        tasmota.set_timer(SPOOLING_LIMIT_CHECK_INTERVAL, /-> self._handleState())
      end
    elif self.state == "top_free_spin"
      self._spoolBrake()
      self.state = "top_braking"
      tasmota.set_timer(TOP_BRAKING_TIME, /-> self._handleState())
    elif self.state == "top_braking"
      self._spoolFreeSpin()
      self.state = "idle"
    else
      self.state = "spooling_up"
      self._handleState()
    end
  end
end

DoorHandleOpener().setup()
