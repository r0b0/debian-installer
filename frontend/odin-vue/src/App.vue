<script setup>
// import BlockDevice from "./components/BlockDevice.vue";</script>
<script>
export default {
  data() {
    return {
      backend_addr: "",
      backend_pin: "",
      logged_in_backend: "",
      required_packages_installed: false,
      login_error: "",
      block_devices: [],
      top_device: "",
      install_to_device_process_key: "",
      install_to_device_status: {},
    }
  },
  methods: {
    login()  {
      this.fetch_from_backend("/login")
          .then(response => {
            this.login_error = "";
            console.debug(response);
            this.logged_in_backend = response.hostname;
            setTimeout(this.check_process_status, 1000, response.subprocess_key, response => {
              if(response.return_code == 0) {
                this.required_packages_installed = response;
              } else {
                this.login_error = response.error || response.output;
              }
            });
            this.get_block_devices();
          })
          .catch(error => {
            // console.error(error);
            this.login_error = `${error}`;
          })
    },
    get_block_devices() {
      this.fetch_from_backend("/block_devices")
          .then(response => {
            console.debug(response);
            this.block_devices = response.blockdevices;
          });
    },
    install_on_device(device_path) {
      this.fetch_from_backend("/install",  {device_path: device_path})
          .then(response => {
            console.debug(response);
            this.install_to_device_process_key = response.subprocess_key;
            setTimeout(this.check_process_status, 1000, response.subprocess_key, response => {
              this.install_to_device_status = response;
            });
          });
    },
    check_process_status(subprocess_key, finished) {
      this.fetch_from_backend("/process_status/" + subprocess_key)
          .then(response => {
            console.debug(response);
            if(response.status == "RUNNING") {
              setTimeout(this.check_process_status, 5000, response.key, finished);
            } else if(response.script == "FINISHED") {
              finished(response);
            }
          })
    },
    fetch_from_backend(path, searchParams={}) {
      const BACKEND_PORT="5000";
      let url = new URL(path, `http://${this.backend_addr}:${BACKEND_PORT}`);
      let cred = btoa(`:${this.backend_pin}`);
      let auth = {"Authorization": `Basic ${cred}`};
      for (const [k, v] of Object.entries(searchParams))
        url.searchParams.append(k, v);
      // url.searchParams.append("pin", this.backend_pin);
      return fetch(url.href, {headers: auth})
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
    }
  }
}
</script>
<template>
  <header>
    Debian Installer
  </header>

  <main>
    <div class="form_line">
      <label for="backend_addr">Backend Address</label>
      <input id="backend_addr" type="text" v-model="backend_addr" :disabled="this.logged_in_backend.length>0"/>
    </div>

    <div class="form_line">
      <label for="backend_pin">Backend PIN</label>
      <input id="backend_pin" type="text" pattern="[0-9]{5}" v-model="backend_pin" :disabled="this.logged_in_backend.length>0"/>
    </div>

    <button @click="login()" :disabled="this.logged_in_backend.length>0">Login</button>
    <div v-if="this.logged_in_backend">Logged in to {{logged_in_backend}}</div>
    <div v-if="this.required_packages_installed">Required packages installed on host</div>
    <div class="error" v-if="this.login_error">{{login_error}}</div>

     <div class="form_line">
      <label for="top_device">Device for Installation</label>
      <select id="top_device"  v-model="top_device">
        <option v-for="item in block_devices" :value="item.path">{{item.path}} {{item.model}} {{item.size}}</option>
      </select>
    </div>

    <div v-if="this.top_device.length>0">Will install debian to device {{top_device}} on {{backend_addr}} (hostname {{logged_in_backend}})</div>

    <button @click="install_on_device(this.top_device)" :disabled="this.top_device.length==0">Install debian on {{top_device}}</button>

    <div>{{install_to_device_status.status}}</div>
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

  header {
    display: flex;
    place-items: center;
    padding-right: calc(var(--section-gap) / 2);
  }

  header .wrapper {
    display: flex;
    place-items: flex-start;
    flex-wrap: wrap;
  }

  .logo {
    margin: 0 2rem 0 0;
  }
}
</style>
