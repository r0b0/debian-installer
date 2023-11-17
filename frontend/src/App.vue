<script>
import Password from "./components/Password.vue";
import timezonesTxt from './assets/timezones.txt?raw';
import {nextTick} from "vue";

export default {
  components: {Password},
  data() {
    return {
      error_message: "",
      subprocesses: {},
      block_devices: [],
      install_to_device_process_key: "",
      install_to_device_status: "",
      overall_status: "",
      running: false,
      finished: false,
      output_reader_connection: null,
      timezones: [],
      
      // values for the installer:
      installer: {
        DISK: "",
        DEBIAN_VERSION: "bookworm",
        USERNAME: "user",
        USER_FULL_NAME: "Debian User",
        USER_PASSWORD: undefined,
        ROOT_PASSWORD: undefined,
        LUKS_PASSWORD: undefined,
        HOSTNAME: "debian",
        TIMEZONE: "UTC",
        ENABLE_SWAP: "partition",
        SWAP_SIZE: 1,
      }
    }
  },
  computed: {
    can_start() {
      let ret = true;
      if(this.error_message.length>0) {
        ret = false;
      }
      for(const [key, value] of Object.entries(this.installer)) {
        if(typeof value === 'undefined') {
          ret = false;
          break;
        }
        if(value.length === 0) {
          ret = false;
          break;
        }
      }
      return ret;
    }
  },
  mounted() {
    this.get_available_timezones();
    this.check_login();
  },
  methods: {
    check_login() {
      this.fetch_from_backend("/login")
        .then(response => {
          if(!response.has_efi) {
            this.error_message = "This system does not appear to use EFI. This installer will not work."
          } else {
            this.error_message = "";
          }
          this.get_block_devices();

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
              device.in_use = false;
              if(device.mountpoint) {
                device.in_use = true;
              }
              if("children" in device) {
                for (const child of device.children) {
                  if (child.mountpoint) {
                    device.in_use = true;
                  }
                }
              }
              if(device.size === "0B") {
                device.ro = true;
              }
              if(device.ro || device.in_use) {
                device.available = false;
              } else {
                device.available = true;
              }
            }
          });
    },
    get_available_timezones() {
      for(const line of timezonesTxt.split("\n")) {
        if(line.startsWith("#")) {
          continue;
        }
        this.timezones.push(line);
      }
    },
    install() {
      this.running = true;
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
            this.finished = false;
            this.output_reader_connection = new WebSocket("ws://localhost:5000/process_output");
            this.output_reader_connection.onmessage = (event) => {
              // console.log("Websocket event received");
              // console.log(event);
              this.install_to_device_status += event.data.toString();
              nextTick(() => {
                this.$refs.process_output_ta.scrollTop = 1000000;
              });
              // console.log(this.install_to_device_status);
            }
            this.output_reader_connection.onclose = (event) => {
              console.log("Websocket connection closed");
              this.check_process_status()
            }
        })
        .catch(error => {
            this.running = false;
            throw Error(error);
        });
    },
    check_process_status() {
      this.fetch_from_backend("/process_status")
          .then(response => {
            console.debug(response);
            this.install_to_device_status = response.output;
            if(response.status == "FINISHED") {
              this.running = false;
              this.finished = true;
              if (response.return_code == 0) {
                this.overall_status = "green";
              } else {
                this.overall_status = "red";
              }
            }
          });
    },
    clear() {
      this.fetch_from_backend("/clear")
          .then(response => {
            console.log(response);
            this.install_to_device_status = "";
            this.overall_status = "";
            this.finished = false;
            this.running = false;
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
  <img alt="banner" class="logo" src="@/assets/Emerald_installer.svg" />

  <header>
    <h1>Opinionated Debian Installer</h1>
    <p>
      This is an <strong>unofficial</strong> installer for the Debian GNU/Linux operating system.
      For more information, read the <a href="https://github.com/r0b0/debian-installer">project page</a>.
    </p>
    <h2>Instructions</h2>
    <ul>
      <li>The installer <strong>will overwrite the entire disk</strong>.</li>
      <li>I repeat, <strong>your entire disk will be overwritten</strong> when you press the Install button.
        There is no way to undo this action.</li>
      <li>If you encounter issues, press the <em>Stop</em> button, open a terminal and investigate.</li>
      <li>Password for the root user in this live system is <code>live</code></li>
      <li>Data in this live system will be persisted, this is not read-only.</li>
    </ul>
    <h2>Features</h2>
    <ul>
      <li>Backports and non-free enabled</li>
      <li>Firmware installed</li>
      <li>Installed on btrfs subvolumes</li>
      <li>Full disk encryption, unlocked by TPM (if available)</li>
      <li>Fast installation using an image</li>
      <li>Browser-based installer</li>
    </ul>
  </header>

  <main>
    <form>
      <fieldset>
        <legend>Installation Target Device</legend>
        <div class="red">{{error_message}}</div>

        <label for="DISK">Device for Installation</label>
        <select :disabled="block_devices.length==0 || running" id="DISK"  v-model="installer.DISK">
          <option v-for="item in block_devices" :value="item.path" :disabled="!item.available">
            {{item.path}} {{item.model}} {{item.size}} {{item.ro ? '(Read Only)' : ''}} {{item.in_use ? '(In Use)' : ''}}
          </option>
        </select>
        <label for="DEBIAN_VERSION">Debian Version</label>
        <select id="DEBIAN_VERSION" v-model="installer.DEBIAN_VERSION" :disabled="running">
          <option value="bookworm" selected>Debian 12 Bookworm</option>
        </select>
      </fieldset>

      <fieldset>
        <legend>Disk Encryption Passphrase</legend>
        <Password v-model="installer.LUKS_PASSWORD" :disabled="running" />
      </fieldset>

      <fieldset>
        <legend>Root User</legend>
        <Password v-model="installer.ROOT_PASSWORD" :disabled="running" />
      </fieldset>

      <fieldset>
        <legend>Regular User</legend>
        <label for="USERNAME">User Name</label>
        <input type="text" id="USERNAME" v-model="installer.USERNAME" :disabled="running">
        <label for="full_name">Full Name</label>
        <input type="text" id="USER_FULL_NAME" v-model="installer.USER_FULL_NAME" :disabled="running">
        <Password v-model="installer.USER_PASSWORD" :disabled="running" />
      </fieldset>

      <fieldset>
        <legend>Configuration</legend>
        <label for="HOSTNAME">Hostname</label>
        <input type="text" id="HOSTNAME" v-model="installer.HOSTNAME" :disabled="running">

        <label for="TIMEZONE">Time Zone</label>
        <select :disabled="timezones.length==0 || running" id="TIMEZONE" v-model="installer.TIMEZONE">
            <option v-for="item in timezones" :value="item">{{ item }}</option>
        </select>

        <label for="ENABLE_SWAP">Swap Space</label>
        <select id="ENABLE_SWAP" v-model="installer.ENABLE_SWAP" :disabled="running">
          <option value="none" selected>None</option>
          <option value="partition" selected>Partition</option>
          <option value="file" selected>File</option>
        </select>

        <label for="SWAP_SIZE">Swap Size (GB)</label>
        <input type="number" id="SWAP_SIZE" v-model="installer.SWAP_SIZE" :disabled="installer.ENABLE_SWAP == 'none' || running">
      </fieldset>

      <fieldset>
        <legend>Process</legend>
        <button type="button" @click="install()"
                :disabled="!can_start || running">
            Install debian on {{ installer.DISK }} <b>OVERWRITING THE WHOLE DRIVE</b>
        </button>
        <br>
        <button type="button" @click="clear()" class="red">Stop</button>
      </fieldset>

      <fieldset>
        <legend>Process Output</legend>
        <textarea ref="process_output_ta" :class="overall_status">{{ install_to_device_status }}</textarea>

        <!-- TODO disable this while not finished instead of hiding -->
        <a v-if="finished" href="http://localhost:5000/download_log" download>Download Log</a>
      </fieldset>
    </form>
  </main>

  <footer>
    <span>Opinionated Debian Installer version 20231105a</span>
    <span>Installer &copy;2022-2023 <a href="https://github.com/r0b0/debian-installer">Robert T</a></span>
    <span>Banner &copy;2022 <a href="https://github.com/julietteTaka/Emerald">Juliette Taka</a></span>
  </footer>
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
  width: 100%;
  padding-bottom: 12pt;
  grid-area: logo;
}

a,
.green {
  text-decoration: none;
  color: #08696b;
  transition: 0.4s;
}

.red {
  color: #cd130f;
}

input:not(.inline), select, textarea {
  width: 100%;
}

textarea {
  height: 20em;
}

label:not(.inline) {
  display: block;
}

.mt-2 {
  margin-top: 12pt;
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
    grid-template-areas:
        "logo logo"
        "header main"
        "footer footer";
    padding: 0 2rem;
  }

  .logo {
    margin: 0 2rem 0 0;
  }

  h1 {
    margin-top: 0;
  }

  footer {
    margin-top: 2em;
    grid-area: footer;
    justify-self: center;
  }
}

footer span {
  margin-right: 2em;
}
</style>
