SELECT * FROM users
WHERE 1=1
{#if filterActive}AND active = :active{/if}
ORDER BY id
