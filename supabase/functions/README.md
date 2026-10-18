# Supabase Edge Functions

## reveal-contact

**Purpose**: Securely reveal private contact information (phone/email) to users with active subscriptions.

**Security Model**: 
- Never expose `private_contacts` table directly through RLS policies
- All contact reveals go through this function which verifies active subscription
- Logs all access in audit_log table for compliance

**Deploy**:
```bash
supabase functions deploy reveal-contact
```

**Set secrets**:
```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
```

**Usage from client**:
```javascript
const { data, error } = await supabase.functions.invoke('reveal-contact', {
  body: { provider_id: 'uuid-here' }
})

if (error) {
  // Handle error - either no subscription or contact not found
  console.error(error)
} else {
  // data.phone and data.email are now available
  console.log(data)
}
```

**TODO before production**:
1. Add rate limiting (e.g., max 10 reveals per hour per user)
2. Consider credit-based system instead of unlimited reveals
3. Add notification to provider when their contact is revealed
4. Implement abuse detection and blocking
5. Add CAPTCHA for first-time reveals
