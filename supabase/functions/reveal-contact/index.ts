// Edge Function: reveal-contact
// PURPOSE: Reveals private contact info (phone/email) only if user has active subscription
// SECURITY: Never expose private_contacts table directly - always go through this function

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Create Supabase client with user's JWT
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: req.headers.get('Authorization')! },
        },
      }
    )

    // Get authenticated user
    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser()

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get provider_id from request
    const { provider_id } = await req.json()

    if (!provider_id) {
      return new Response(
        JSON.stringify({ error: 'provider_id required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if user has active subscription
    const { data: subscription, error: subError } = await supabaseClient
      .from('subscriptions')
      .select('*')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .gte('ends_at', new Date().toISOString())
      .single()

    if (subError || !subscription) {
      return new Response(
        JSON.stringify({
          error: 'Active subscription required',
          message: 'You need an active subscription to view contact details'
        }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // TODO: Log this access in audit_log table for compliance
    // TODO: Implement rate limiting per user to prevent abuse
    // TODO: Consider charging credits per reveal instead of unlimited access

    // Fetch private contact using service_role (bypasses RLS)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { data: contact, error: contactError } = await supabaseAdmin
      .from('private_contacts')
      .select('phone, email')
      .eq('user_id', provider_id)
      .single()

    if (contactError || !contact) {
      return new Response(
        JSON.stringify({ error: 'Contact not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Log the access for audit trail
    await supabaseAdmin
      .from('audit_log')
      .insert({
        user_id: user.id,
        action: 'reveal_contact',
        table_name: 'private_contacts',
        record_id: provider_id,
        new_data: { provider_id },
        ip_address: req.headers.get('x-forwarded-for'),
        user_agent: req.headers.get('user-agent')
      })

    return new Response(
      JSON.stringify({
        phone: contact.phone,
        email: contact.email,
        revealed_at: new Date().toISOString()
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
