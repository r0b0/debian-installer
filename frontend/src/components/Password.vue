<!--
Opinionated Debian Installer
Copyright (C) 2022-2025 Robert T.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
-->

<template>
  <label for="pwd_1">Password</label>
  <input type="password" id="pwd_1" v-model="pwd_1" @input="data_update" :class="input_class" :disabled="disabledInput">

  <label for="pwd_2">Password (repeat)</label>
  <input type="password" id="pwd_2" v-model="pwd_2" @input="data_update" :class="input_class" :disabled="disabledInput">

  <input v-if="isMain" type="checkbox" id="USE_SAME" @change="use_same_update" class="inline">
  <label v-if="isMain" for="USE_SAME" class="inline">Use the same password for everything</label>
  <br v-if="isMain">

  <div class="error" v-if="error_message.length>0">{{error_message}}</div>
</template>

<script>
import {inject} from "vue";

export default {
  name: "Password",
  props: ['modelValue', 'disabled', 'isMain'],
  emits: ['update:modelValue'],
  data() {
    return {
      pwd_1: "",
      pwd_2: "",
      error_message: "",
      input_class: "",
    }
  },
  setup() {
    const singlePasswordActive = inject('singlePasswordActive');
    const singlePasswordValue = inject('singlePasswordValue');
    return {singlePasswordActive, singlePasswordValue}
  },
  methods: {
    data_update() {
      if(this.pwd_1 === this.pwd_2) {
        this.error_message = "";
        this.input_class = "";
        this.$emit('update:modelValue', this.pwd_1);
        if(this.singlePasswordActive)
          this.singlePasswordValue = this.pwd_1;
      } else {
        this.error_message = "Passwords do not match";
        this.input_class = "error";
        this.$emit('update:modelValue', undefined);
      }
    },
    use_same_update(evt) {
      this.singlePasswordActive = evt.target.checked;
    }
  },
  computed: {
    disabledInput() {
      if(this.disabled)
        return true;
      if(this.isMain)
        return false;
      return !!this.singlePasswordActive;
    }
  },
  watch: {
    singlePasswordValue(v) {
      if(this.isMain)
        return;
      if(!this.singlePasswordActive)
        return;
      this.pwd_1 = v;
      this.pwd_2 = v;
      this.$emit('update:modelValue', this.pwd_1);
    },
    singlePasswordActive(v) {
      console.debug(v);
      if(this.isMain && this.pwd_1 === this.pwd_2) {
        this.singlePasswordValue = this.pwd_1;
        return;
      }
      if(!v)
        return;
      this.pwd_1 = this.singlePasswordValue;
      this.pwd_2 = this.singlePasswordValue;
      this.$emit('update:modelValue', this.pwd_1);
    }
  }
}
</script>

<style scoped>
div.error {
  color: #cd130f;
}
input.error {
  border-color: #cd130f;
}

</style>
