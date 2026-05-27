<script lang="ts">
  import { page } from '$app/stores';
  import AccountList from '$lib/components/AccountList.svelte';
</script>

<AccountList acct={$page.params.acct ?? ''} kind="followers" />
