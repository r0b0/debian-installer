<script setup>
// import BlockDevice from "./components/BlockDevice.vue";</script>
<script>
export default {
  data() {
    return {
      backend_addr: "",
      backend_pin: "",
      logged_in_backend: "",
      block_devices: [],
      top_device: ""
    }
  },
  methods: {
    login()  {
      this.fetch_from_backend("/login")
          .then(response => {
            console.debug(response);
            this.logged_in_backend = response.address;
            this.get_block_devices();
          })
    },
    get_block_devices() {
      this.fetch_from_backend("/block_devices")
          .then(response => {
            console.debug(response);
            this.block_devices = response.blockdevices;
          });
    },

    fetch_from_backend(path) {
      const BACKEND_PORT="5000";
      let url = new URL(path, `http://${this.backend_addr}:${BACKEND_PORT}`);
      url.searchParams.append("pin", this.backend_pin);
      return fetch(url.href)
          .then(response => response.json());
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
      <input id="backend_pin" type="number" v-model="backend_pin" :disabled="this.logged_in_backend.length>0"/>
    </div>

    <button @click="login()" :disabled="this.logged_in_backend.length>0">Login</button>
    <div v-if="this.logged_in_backend">Logged in to {{logged_in_backend}}</div>

     <div class="form_line">
      <label for="top_device">Device for Installation</label>
      <select id="top_device"  v-model="top_device">
        <option v-for="item in block_devices" :value="item.path">{{item.path}} ({{item.size}})</option>
      </select>
    </div>

    <div v-if="this.top_device.length>0">Will install debian to device {{top_device}} on {{logged_in_backend}}</div>
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
