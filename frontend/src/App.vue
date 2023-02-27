<script>
import Header from "./components/Header.vue";
import Password from "./components/Password.vue";
import Subprocess from "./components/Subprocess.vue";

export default {
  components: {Header, Password, Subprocess},
  data() {
    return {
      error_message: "",
      subprocesses: {},
      block_devices: [],
      install_to_device_process_key: "",
      install_to_device_status: {},
      timezones: [],
      
      // values for the installer:
      DISK: "",
      USERNAME: "user",
      USER_FULL_NAME: "Debian User",
      USER_PASSWORD: undefined,
      ROOT_PASSWORD: undefined,
      LUKS_PASSWORD: undefined,
      HOSTNAME: "debian",
      TIMEZONE: "UTC",
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
      for(const item of ["DISK", "LUKS_PASSWORD", "ROOT_PASSWORD", "USERNAME", "USER_FULL_NAME", "USER_PASSWORD", "HOSTNAME", "TIMEZONE"]) {
        data.append(item, this[item]);
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
            // TODO
        })
        .catch(error => {
            throw Error(error);
        });
    },
    check_process_status(subprocess_key, finished) {
      this.fetch_from_backend("/process_status/" + subprocess_key)
          .then(response => {
            console.debug(response);
            this.subprocesses[subprocess_key] = response;
            if(response.status == "RUNNING") {
              setTimeout(this.check_process_status, 5000, response.key, finished);
            } else if(response.status == "FINISHED") {
              finished(response);
            } else {
              console.error("Unknown response status" + response.status);
            }
          })
    },
    fetch_from_backend(path, searchParams={}) {
      let url = new URL(path, 'http://localhost:5000');
      for (const [k, v] of Object.entries(searchParams))
        url.searchParams.append(k, v);
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
        <select :disabled="block_devices.length==0" id="DISK"  v-model="DISK">
          <option v-for="item in block_devices" :value="item.path" :disabled="item.ro">
            {{item.path}} {{item.model}} {{item.size}} {{item.ro ? '(Read Only)' : ''}}
          </option>
        </select>
      </fieldset>

      <fieldset>
        <legend>Disk Encryption Passphrase</legend>
        <Password v-model="LUKS_PASSWORD" />
      </fieldset>

      <fieldset>
        <legend>Root User</legend>
        <Password v-model="ROOT_PASSWORD" />
      </fieldset>

      <fieldset>
        <legend>Regular User</legend>
        <label for="USERNAME">User Name</label>
        <input type="text" id="USERNAME" v-model="USERNAME">
        <label for="full_name">Full Name</label>
        <input type="text" id="USER_FULL_NAME" v-model="USER_FULL_NAME">
        <Password v-model="USER_PASSWORD" />
      </fieldset>
      
      <fieldset>
        <legend>Configuration</legend>
        <label for="HOSTNAME">Hostname</label>
        <input type="text" id="HOSTNAME" v-model="HOSTNAME">
        <label for="TIMEZONE">Time Zone</label>
        <select :disabled="timezones.length==0" id="TIMEZONE" v-model="TIMEZONE">
            <option v-for="item in timezones" :value="item">{{ item }}</option>
        </select>
      </fieldset>
      
        <button type="button" @click="install()"
                :disabled="DISK.length==0">
            Install debian on {{DISK}} <b>OVERWRITING THE WHOLE DRIVE</b>
        </button>

        <div class="green">{{install_to_device_status.status}}</div>

    </form>
    
    <Subprocess v-for="s in subprocesses" :data="s" />
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
  color: hsla(160, 100%, 37%, 1);
  transition: 0.4s;
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
