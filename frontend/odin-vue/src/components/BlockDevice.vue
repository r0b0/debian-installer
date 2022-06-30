<template>
<table>
  <thead>
    <tr>
      <td>Name</td>
      <td>Size</td>
      <td>Type</td>
    </tr>
  </thead>
  <tbody>
    <tr class="disk">
      <td>{{data.path}}</td>
      <td>{{data.size}}</td>
      <td>{{data.pttype}}</td>
    </tr>
    <tr v-for="partition in data.children" class="partition">
      <td>{{partition.path}}</td>
      <td>{{partition.size}}</td>
      <td>{{partition.fstype}} {{partition.fsver}}</td>
    </tr>
  </tbody>
</table>
</template>

<script>
export default {
  name: "BlockDevice",
  props: {
    data: Object
  }
}
</script>

<style scoped>

</style>