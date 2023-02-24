<template>
  <label for="root_pwd_1">Password</label>
  <input type="password" id="pwd_1" v-model="pwd_1" @input="data_update" :class="input_class">

  <label for="root_pwd_2">Password (repeat)</label>
  <input type="password" id="pwd_2" v-model="pwd_2" @input="data_update" :class="input_class">

  <div class="error" v-if="error_message.length>0">{{error_message}}</div>
</template>

<script>
export default {
  name: "Password",
  props: ['modelValue'],
  emits: ['update:modelValue'],
  data() {
    return {
      pwd_1: "",
      pwd_2: "",
      error_message: "",
      input_class: "",
    }
  },
  methods: {
    data_update() {
      if(this.pwd_1 === this.pwd_2) {
        this.error_message = "";
        this.input_class = "";
        this.$emit('update:modelValue', this.pwd_1);
      } else {
        this.error_message = "Passwords do not match";
        this.input_class = "error";
        this.$emit('update:modelValue', undefined);
      }
    }
  }
}
</script>

<style scoped>
div.error {
  color: red;
}
input.error {
  border-color: red;;
}

</style>