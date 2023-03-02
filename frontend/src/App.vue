<script>
import Header from "./components/Header.vue";
import Password from "./components/Password.vue";

export default {
  components: {Header, Password},
  data() {
    return {
      error_message: "",
      subprocesses: {},
      block_devices: [],
      install_to_device_process_key: "",
      install_to_device_status: "",
      overall_status: "",
      output_reader_connection: null,
      timezones: [],
      
      // values for the installer:
      installer: {
        DISK: "",
        USERNAME: "user",
        USER_FULL_NAME: "Debian User",
        USER_PASSWORD: undefined,
        ROOT_PASSWORD: undefined,
        LUKS_PASSWORD: undefined,
        HOSTNAME: "debian",
        TIMEZONE: "UTC",
      }
    }
  },
  computed: {
    can_start() {
      let ret = true;
      for(const [key, value] of Object.entries(this.installer)) {
        if(typeof value === 'undefined')
          ret = false;
      }
      return ret;
    }
  },
  mounted() {
    this.check_login();
  },
  methods: {
    check_login() {
      this.fetch_from_backend("/login")
        .then(() => {
          this.error_message = "";
          this.get_block_devices();
          this.get_available_timezones();
        })
        .catch(() => {
          this.error_message = "Backend not yet available";
          console.info("Backend not yet available");
          setTimeout(this.check_login, 1000);
        });
    },
    get_block_devices() {
      this.fetch_from_backend("/block_devices")
          .then(response => {
            console.debug(response);
            this.block_devices = response.blockdevices;
            for(const device of this.block_devices) {
              if(device.mountpoint) {
                device.ro = true;
              }
              for(const child of device.children) {
                if(child.mountpoint) {
                  device.ro = true;
                }
              }
            }
          });
    },
    get_available_timezones() {
      this.fetch_from_backend("/timezones")
          .then(response => {
            console.debug(response);
            this.timezones = response.timezones;
          });
    },
    install() {
      let data = new FormData();
      for(const [key, value] of Object.entries(this.installer)) {
        data.append(key, value);
      }
      fetch("http://localhost:5000/install", {"method": "POST", "body": data})
        .then(response => {
            //console.debug(response);
            if(!response.ok) {
                throw Error(response.statusText);
            }
            return response.json();
        })
        .then(result => {
            console.debug(result);
            this.output_reader_connection = new WebSocket("ws://localhost:5000/process_output");
            this.output_reader_connection.onmessage = (event) => {
              console.log("Websocket event received");
              // console.log(event);
              this.install_to_device_status += event.data.toString();
              window.scrollTo(0, document.body.scrollHeight);
              // console.log(this.install_to_device_status);
            }
            this.output_reader_connection.onclose = (event) => {
              console.log("Websocket connection closed");
              this.check_process_status()
            }
        })
        .catch(error => {
            throw Error(error);
        });
    },
    check_process_status() {
      this.fetch_from_backend("/process_status")
          .then(response => {
            console.debug(response);
            this.install_to_device_status = response.output;
            if(response.return_code == 0) {
              this.overall_status = "green";
            } else {
              this.overall_status = "red";
            }
          });
    },
    clear() {
      this.fetch_from_backend("/clear")
          .then(response => {
            console.log(response);
            this.install_to_device_status = "";
          })
          .catch(error => {
            throw Error(error);
          });
    },
    fetch_from_backend(path) {
      let url = new URL(path, 'http://localhost:5000');
      return fetch(url.href)
          .then(response => {
            if(!response.ok) {
              // console.error(response);
              throw Error(response.statusText);
            }
            return response.json();
          })
          .catch(error => {
            // console.error(error);
            throw Error(error);
          });
    },
  }
}
</script>
<template>
  <Header />

  <main>
    <form>
      <fieldset>
        <legend>Installation Target Device</legend>
        <div class="green">{{error_message}}</div>

        <label for="DISK">Device for Installation</label>
        <select :disabled="block_devices.length==0" id="DISK"  v-model="installer.DISK">
          <option v-for="item in block_devices" :value="item.path" :disabled="item.ro">
            {{item.path}} {{item.model}} {{item.size}} {{item.ro ? '(Read Only)' : ''}}
          </option>
        </select>
      </fieldset>

      <fieldset>
        <legend>Disk Encryption Passphrase</legend>
        <Password v-model="installer.LUKS_PASSWORD" />
      </fieldset>

      <fieldset>
        <legend>Root User</legend>
        <Password v-model="installer.ROOT_PASSWORD" />
      </fieldset>

      <fieldset>
        <legend>Regular User</legend>
        <label for="USERNAME">User Name</label>
        <input type="text" id="USERNAME" v-model="installer.USERNAME">
        <label for="full_name">Full Name</label>
        <input type="text" id="USER_FULL_NAME" v-model="installer.USER_FULL_NAME">
        <Password v-model="installer.USER_PASSWORD" />
      </fieldset>

      <fieldset>
        <legend>Configuration</legend>
        <label for="HOSTNAME">Hostname</label>
        <input type="text" id="HOSTNAME" v-model="installer.HOSTNAME">
        <label for="TIMEZONE">Time Zone</label>
        <select :disabled="timezones.length==0" id="TIMEZONE" v-model="installer.TIMEZONE">
            <option v-for="item in timezones" :value="item">{{ item }}</option>
        </select>
      </fieldset>


      <fieldset>
        <legend>Process</legend>
        <button type="button" @click="install()"
                :disabled="!can_start">
            Install debian on {{ installer.DISK }} <b>OVERWRITING THE WHOLE DRIVE</b>
        </button>
        <br>
        <button type="button" @click="clear()" class="red">Stop</button>
      </fieldset>

      <fieldset>
        <legend>Process Output</legend>
        <pre :class="overall_status">{{ install_to_device_status }}</pre>
      </fieldset>

    </form>
  </main>
</template>

<style>
@import './assets/base.css';

#app {
  max-width: 1280px;
  margin: 0 auto;
  padding: 2rem;

  font-weight: normal;
}

header {
  line-height: 1.5;
}

.logo {
  display: block;
  margin: 0 auto 2rem;
}

a,
.green {
  text-decoration: none;
  color: hsl(170, 100%, 37%);
  transition: 0.4s;
}

.red {
  color: #BD0000FF;
}

input:not(.inline), select {
  width: 100%;
}

label:not(.inline) {
  display: block;
}

button {
  margin-top: 0.5em;
}

@media (hover: hover) {
  a:hover {
    background-color: hsla(160, 100%, 37%, 0.2);
  }
}

@media (min-width: 1024px) {
  body {
    display: flex;
    place-items: center;
  }

  #app {
    display: grid;
    grid-template-columns: 1fr 1fr;
    padding: 0 2rem;
  }

  .logo {
    margin: 0 2rem 0 0;
  }
}
</style>
