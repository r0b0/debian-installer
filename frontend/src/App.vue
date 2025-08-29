<script>
import Password from "./components/Password.vue";
import timezonesTxt from './assets/timezones.txt?raw';
import {nextTick, provide, ref} from "vue";

export default {
  components: {Password},
  data() {
    return {
      error_message: "",
      subprocesses: {},
      block_devices: [],
      install_to_device_process_key: "",
      install_to_device_status: "",
      has_nvidia: false,
      sb_state: "",
      want_nvidia: false,
      overall_status: "",
      running: false,
      finished: false,
      output_reader_connection: null,
      timezones: [],
      
      // values for the installer:
      installer: {
        DISK: undefined,
        USERNAME: undefined,
        USER_FULL_NAME: undefined,
        USER_PASSWORD: undefined,
        ROOT_PASSWORD: undefined,
        LUKS_PASSWORD: undefined,
        ENABLE_MOK_SIGNED_UKI: undefined,
        MOK_ENROLL_PASSWORD: undefined,
        DISABLE_LUKS: undefined,
        ENABLE_TPM: undefined,
        HOSTNAME: undefined,
        TIMEZONE: undefined,
        SWAP_SIZE: undefined,
        NVIDIA_PACKAGE: " ",  // will be changed in install()
        ENABLE_POPCON: undefined,
      }
    }
  },
  computed: {
    can_start() {
      let ret = true;
      if(this.error_message.length>0) {
        ret = false;
      }
      /*
      // XXX this is currently broken
      for(const [key, value] of Object.entries(this.installer)) {
        if(key === "LUKS_PASSWORD" && this.installer.DISABLE_LUKS) {
          continue;
        }
        if(typeof value === 'undefined') {
          ret = false;
          break;
        }
        if(value.length === 0) {
          ret = false;
          break;
        }
      }
       */
      return ret;
    },
    hostname() {
      return window.location.hostname;
    }
  },
  setup() {
    provide('singlePasswordActive', ref(false));
    provide('singlePasswordValue', ref(""));
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
          if(response.running) {
            this.running = true;
            this.finished = false;
          } else {
            this.running = false;
          }
          this.has_nvidia = response.has_nvidia;
          this.want_nvidia = response.has_nvidia;
          this.sb_state = response.sb_state;

          for(const [key, value] of Object.entries(this.installer)) {
            if(key in response.environ) {
              if(key === "NVIDIA_PACKAGE" && response.environ[key] === "") {
                continue; // because empty value would prevent can_start()
              } else if(key === "NVIDIA_PACKAGE" && response.environ[key].length > 0) {
                this.want_nvidia = true;
                this.has_nvidia = true;
              }
              console.debug(`Setting '${key}' from backend to '${response.environ[key]}'`);
              this.installer[key] = response.environ[key];
            }
          }
          
          this.get_block_devices();
          this.read_process_output();

        })
        .catch((error) => {
          this.error_message = "Backend not yet available";
          console.info("Backend not yet available");
          console.error(error);
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
          }); // TODO check errors
    },
    get_available_timezones() {
      for(const line of timezonesTxt.split("\n")) {
        if(line.startsWith("#")) {
          continue;
        }
        this.timezones.push(line);
      }
    },
    read_process_output() {
      this.output_reader_connection = new WebSocket(`ws://${this.hostname}:5000/process_output`);
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
        this.check_process_status();
      }
    },
    install() {
      this.running = true;
      if(this.installer["NVIDIA_PACKAGE"] !== " ") {
        // we received a package name from the back-end, nothing to do here
      } else if(this.want_nvidia) {
        this.installer["NVIDIA_PACKAGE"] = "nvidia-driver";
      } else {
        this.installer["NVIDIA_PACKAGE"] = "";
      }
      let data = new FormData();
      for(const [key, value] of Object.entries(this.installer)) {
        data.append(key, value);
      }
      fetch(`http://${this.hostname}:5000/install`, {"method": "POST", "body": data})
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
            
        })
        .catch(error => {
            this.running = false;
            // TODO set this.error_message
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
                this.$refs.completed_dialog.showModal();
              } else {
                this.overall_status = "red";
              }
            }
          }); // TODO error checking
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
            // TODO set this.error_message
            throw Error(error);
          });
    },
    fetch_from_backend(path) {
      let url = new URL(path, `http://${this.hostname}:5000`);
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
            // TODO set this.error_message
            throw Error(error);
          });
    },
  }
}
</script>
<template>
  <img alt="banner" class="logo" src="@/assets/Ceratopsian_installer.svg" />

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
      <div class="red">{{error_message}}</div>
      <fieldset>
        <legend>Installation Target Device</legend>
        <label for="DISK">Device for Installation</label>
        <select :disabled="block_devices.length==0 || running" id="DISK"  v-model="installer.DISK">
          <option v-for="item in block_devices" :value="item.path" :disabled="!item.available">
            {{item.path}} {{item.model}} {{item.size}} {{item.ro ? '(Read Only)' : ''}} {{item.in_use ? '(In Use)' : ''}}
          </option>
        </select>
        <label for="DEBIAN_VERSION">Debian Version</label>
        <select id="DEBIAN_VERSION">
          <option value="trixie" selected>Debian 13 Trixie</option>
        </select>
      </fieldset>

      <fieldset>
        <legend>Disk Encryption</legend>
        <input type="checkbox" v-model="installer.DISABLE_LUKS" id="DISABLE_LUKS" class="inline">
        <label for="DISABLE_LUKS" class="inline">Device already encrypted</label>

        <!-- TODO: skip if DISABLE_LUKS -->
        <Password v-model="installer.LUKS_PASSWORD" :disabled="running" :is-main="true"/>

        <input type="checkbox" v-model="installer.ENABLE_TPM" id="ENABLE_TPM" class="inline mt-3">
        <label for="ENABLE_TPM" class="inline mt-3">Unlock disk with TPM</label>
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

        <label for="SWAP_SIZE">Swap Size (GB) - Set to 0 to Disable</label>
        <input type="number" id="SWAP_SIZE" v-model="installer.SWAP_SIZE" :disabled="running">

        <input type="checkbox" v-model="want_nvidia" id="WANT_NVIDIA" class="inline mt-3" :disabled="!has_nvidia || running">
        <label for="WANT_NVIDIA" class="inline mt-3">Install the proprietary NVIDIA Accelerated Linux Graphics Driver</label>

        <br>
        <input type="checkbox" v-model="installer.ENABLE_POPCON" id="ENABLE_POPCON" class="inline mt-3" :disabled="running">
        <label for="ENABLE_POPCON" class="inline mt-3">Participate in the <a href="https://popcon.debian.org/" target="_blank">debian package usage survey</a></label>
      </fieldset>

      <fieldset>
        <legend>SecureBoot</legend>

        <label for="sb_state">Current Status</label>
        <input type="text" id="sb_state" disabled v-model="sb_state">

        <input type="checkbox" v-model="installer.ENABLE_MOK_SIGNED_UKI" class="inline mt-3" :disabled="running" />
        <label for="ENABLE_MOK_SIGNED_UKI" class="inline mt-3">Enable MOK-signed UKI</label>

        <label class="mt-3">Machine-Owner-Keys Enrollment Password</label>
        <Password v-model="installer.MOK_ENROLL_PASSWORD" :disabled="running || !installer.ENABLE_MOK_SIGNED_UKI" />

        <button type="button" @click="this.$refs.mok_dialog.showModal()" class="mt-3">Explanation</button>
      </fieldset>

      <fieldset>
        <legend>Process</legend>
        <button type="button" @click="install()"
                :disabled="!can_start || running">
            Install debian on {{ installer.DISK }} <b>OVERWRITING THE WHOLE DRIVE</b>
        </button>
        <br>
        <button type="button" @click="clear()" class="mt-2 red">Stop</button>
      </fieldset>

      <fieldset>
        <legend>Process Output</legend>
        <textarea ref="process_output_ta" :class="overall_status">{{ install_to_device_status }}</textarea>

        <!-- TODO disable this while not finished instead of hiding -->
        <a v-if="finished" :href="'http://' + hostname + ':5000/download_log'" download>Download Log</a>
      </fieldset>
    </form>
  </main>

  <footer>
    <span>Opinionated Debian Installer version 20250818a</span>
    <span>Installer &copy;2022-2025 <a href="https://github.com/r0b0/debian-installer">Robert T</a></span>
    <span>Banner &copy;2024 <a href="https://github.com/pccouper/trixie">Elise Couper</a></span>
  </footer>

  <dialog ref="completed_dialog">
    <p>
      Debian successfully installed. You can now turn off your computer, remove the installation media and start it again.
    </p>
    <button class="right-align mt-2" @click="$refs.completed_dialog.close()">Close</button>
  </dialog>
  <dialog ref="mok_dialog">
    <p>
      If you keep the <i>Enable MOK-signed UKI</i> box unchecked, a simple mode will be used, where the shim, systemd-boot
      and kernel are signed by Microsoft and Debian.
      The initrd file will not be signed.
    </p>
    <p>
      If you check the box, the fully-authenticated boot will be enabled.
      This is the most secure option.
      The installer will generate your Machine Owner Key (MOK) and configure the system to use Unified Kernel Image (UKI) which contains both the kernel and initrd.
      The MOK will be used to sign the UKI so that all the files involved in the boot process are authenticated.
    </p>
    <p>
      After the installation, on the next boot, you will be asked to enroll your MOK.
      Use the password you provided in the installer.
      See the screenshots of the process below:
      <img src="@/assets/Screenshot_mok_import_01.png" alt="mok enroll screenshot 1" width="320" />
      <img src="@/assets/Screenshot_mok_import_02.png" alt="mok enroll screenshot 2" width="320" />
      <img src="@/assets/Screenshot_mok_import_03.png" alt="mok enroll screenshot 3" width="320" />
      <img src="@/assets/Screenshot_mok_import_04.png" alt="mok enroll screenshot 4" width="320" />
      <img src="@/assets/Screenshot_mok_import_05.png" alt="mok enroll screenshot 5" width="320" />
      <img src="@/assets/Screenshot_mok_import_06.png" alt="mok enroll screenshot 6" width="320" />
    </p>
    <button class="right-align mt-2" @click="$refs.mok_dialog.close()">Close</button>
  </dialog>
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
  color: #26475b;
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
  margin-top: 0.5em;
}

.mt-3 {
  margin-top: 1em;
}

.right-align {
  float: right;
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
