<template>
<ul>
  <li><b>Command:</b> {{data.command}}</li>
  <li><b>Key:</b> {{data.key}}</li>
  <li><b>Status:</b> {{data.status}}</li>
  <li><b>Return Code:</b> {{data.return_code}}</li>
  <li><b>Standard Output:</b> <pre>{{data.output}}</pre></li>
  <li><b>Standard Errors:</b> <pre>{{data.error}}</pre></li>
</ul>
</template>

<script>
export default {
  name: "Subprocess",
  props: {
    data: Object,
  }
}
</script>

<style scoped>
ul {
  border-width: 2px;
  border-style: groove;
  margin-top: 1em;
}
</style>