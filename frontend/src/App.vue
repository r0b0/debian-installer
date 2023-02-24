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
      top_device: "",
      install_to_device_process_key: "",
      install_to_device_status: {},
      luks_password: undefined,
      root_password: undefined,
      user_name: "user",
      user_full_name: "Debian User",
      user_password: undefined,
      hostname: "debian",
      tasksel_tasks: [],
      tasks_to_install: [],
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
          this.get_available_tasksel_tasks();
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
    get_available_tasksel_tasks() {
      this.fetch_from_backend("/available-tasksel-tasks")
          .then(response => {
            console.debug(response);
            this.tasksel_tasks = response.available_tasksel_tasks;
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
    set_encryption_password() {
      // TODO
    },
    set_root_password() {
      // TODO
    },
    set_user_password() {
      // TODO
    },
    run_tasksel() {
      // TODO
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

        <label for="top_device">Device for Installation</label>
        <select :disabled="block_devices.length==0" id="top_device"  v-model="top_device">
          <option v-for="item in block_devices" :value="item.path" :disabled="item.ro">
            {{item.path}} {{item.model}} {{item.size}} {{item.ro ? '(Read Only)' : ''}}
          </option>
        </select>
      </fieldset>

      <fieldset>
        <legend>Disk Encryption Passphrase</legend>
        <Password v-model="luks_password" />
      </fieldset>

      <fieldset>
        <legend>Root User</legend>
        <Password v-model="root_password" />
      </fieldset>

      <fieldset>
        <legend>Regular User</legend>
        <label for="full_name">Full Name</label>
        <input type="text" id="user_full_name" v-model="user_full_name">
        <label for="user_name">Name</label>
        <input type="text" id="user_name" v-model="user_name">
        <Password v-model="user_password" />
      </fieldset>
      
      <fieldset>
        <legend>Configuration</legend>
        <label for="hostname">Hostname</label>
        <input type="text" id="hostname" v-model="hostname">
      </fieldset>

      <!--
      <fieldset>
        <legend>Installation Components</legend>

        <div v-for="item in tasksel_tasks">
          <input class="inline" type="checkbox" v-model="tasks_to_install" :id="item.name" :value="item.name">
          <label class="inline" :for="item.name">{{item.desc}}</label>
        </div>

        <button type="button" @click="run_tasksel()">Confirm</button>
      </fieldset>
      -->
      
        <button type="button" @click="install_on_device(top_device)"
                :disabled="top_device.length==0">
            Install debian on {{top_device}} <b>OVERWRITING THE WHOLE DRIVE</b>
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
