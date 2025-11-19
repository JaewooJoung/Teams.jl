#=
    Teams

A high-performance Julia module for sending Microsoft Teams messages via webhook connectors.
Optimized for type stability, memory efficiency, and idiomatic Julia patterns.
=#
module Teams

using HTTP
using JSON3

export TeamsException, CardSection, PotentialAction, ConnectorCard, format_url

# Custom exception type
struct TeamsException <: Exception
    message::String
end

Base.showerror(io::IO, e::TeamsException) = print(io, "TeamsException: ", e.message)

# ============================================================================
# Choice struct (immutable for better performance)
# ============================================================================
struct Choice
    display::String
    value::String
end

# ============================================================================
# CardSection - Mutable for builder pattern but optimized
# ============================================================================
mutable struct CardSection
    payload::Dict{String, Any}
    
    # Pre-allocate with reasonable initial capacity
    CardSection() = new(Dict{String, Any}())
end

# Chainable methods using @inline for better performance
@inline function title(self::CardSection, stitle::String)::CardSection
    self.payload["title"] = stitle
    return self
end

@inline function activity_title(self::CardSection, sactivity_title::String)::CardSection
    self.payload["activityTitle"] = sactivity_title
    return self
end

@inline function activity_subtitle(self::CardSection, sactivity_subtitle::String)::CardSection
    self.payload["activitySubtitle"] = sactivity_subtitle
    return self
end

@inline function activity_image(self::CardSection, sactivity_image::String)::CardSection
    self.payload["activityImage"] = sactivity_image
    return self
end

@inline function activity_text(self::CardSection, sactivity_text::String)::CardSection
    self.payload["activityText"] = sactivity_text
    return self
end

function add_fact(self::CardSection, fact_name::String, fact_value::String)::CardSection
    facts = get!(() -> Vector{Dict{String, String}}(), self.payload, "facts")
    push!(facts, Dict("name" => fact_name, "value" => fact_value))
    return self
end

function add_image(self::CardSection, simage::String; image_title::Union{String, Nothing}=nothing)::CardSection
    images = get!(() -> Vector{Dict{String, String}}(), self.payload, "images")
    imobj = Dict{String, String}("image" => simage)
    if !isnothing(image_title)
        imobj["title"] = image_title
    end
    push!(images, imobj)
    return self
end

@inline function text(self::CardSection, stext::String)::CardSection
    self.payload["text"] = stext
    return self
end

function link_button(self::CardSection, button_text::String, button_url::String)::CardSection
    self.payload["potentialAction"] = [
        Dict{String, Any}(
            "@context" => "http://schema.org",
            "@type" => "ViewAction",
            "name" => button_text,
            "target" => [button_url]
        )
    ]
    return self
end

@inline function disable_markdown(self::CardSection)::CardSection
    self.payload["markdown"] = false
    return self
end

@inline function enable_markdown(self::CardSection)::CardSection
    self.payload["markdown"] = true
    return self
end

# More efficient to return the Dict directly
@inline dump_section(self::CardSection)::Dict{String, Any} = self.payload

# ============================================================================
# PotentialAction - Optimized with pre-allocated vectors
# ============================================================================
mutable struct PotentialAction
    payload::Dict{String, Any}
    choices::Vector{Choice}
    
    function PotentialAction(name::String, _type::String="ActionCard")
        payload = Dict{String, Any}(
            "@type" => _type,
            "name" => name
        )
        new(payload, Choice[])
    end
end

function add_input(self::PotentialAction, _type::String, _id::String, input_title::String; 
                   is_multiline::Union{Bool, Nothing}=nothing)::PotentialAction
    inputs = get!(() -> Vector{Dict{String, Any}}(), self.payload, "inputs")
    
    input_dict = Dict{String, Any}(
        "@type" => _type,
        "id" => _id,
        "title" => input_title
    )
    
    if !isnothing(is_multiline)
        input_dict["isMultiline"] = is_multiline
    end
    
    if !isempty(self.choices)
        input_dict["choices"] = [Dict("display" => c.display, "value" => c.value) for c in self.choices]
    end
    
    push!(inputs, input_dict)
    return self
end

function add_action(self::PotentialAction, _type::String, _name::String, _target::String; 
                    _body::Union{String, Nothing}=nothing)::PotentialAction
    actions = get!(() -> Vector{Dict{String, Any}}(), self.payload, "actions")
    
    action = Dict{String, Any}(
        "@type" => _type,
        "name" => _name,
        "target" => _target
    )
    
    if !isnothing(_body)
        action["body"] = _body
    end
    
    push!(actions, action)
    return self
end

function add_open_uri(self::PotentialAction, _name::String, _targets::Vector{Dict{String, String}})::PotentialAction
    if !isa(_targets, Vector{<:Dict})
        throw(ArgumentError("Target must be of type Vector{Dict{String, String}}"))
    end
    
    self.payload["@type"] = "OpenUri"
    self.payload["name"] = _name
    self.payload["targets"] = _targets
    return self
end

@inline function add_choice(self::PotentialAction, display::String, value::String)::PotentialAction
    push!(self.choices, Choice(display, value))
    return self
end

@inline dump_potential_action(self::PotentialAction)::Dict{String, Any} = self.payload

# ============================================================================
# ConnectorCard - Main card object with optimized HTTP handling
# ============================================================================
mutable struct ConnectorCard
    payload::Dict{String, Any}
    hookurl::String
    proxies::Union{Dict{String, String}, Nothing}
    http_timeout::Int
    verify::Bool
    last_http_response::Union{HTTP.Response, Nothing}
    
    function ConnectorCard(hookurl::String;
                          http_proxy::Union{String, Nothing}=nothing,
                          https_proxy::Union{String, Nothing}=nothing,
                          http_timeout::Int=60,
                          verify::Bool=true)
        
        # Validate webhook URL
        if isempty(hookurl)
            throw(ArgumentError("Webhook URL cannot be empty"))
        end
        
        payload = Dict{String, Any}()
        payload["@type"] = "MessageCard"
        payload["@context"] = "https://schema.org/extensions"
        
        proxies = nothing
        if !isnothing(http_proxy) || !isnothing(https_proxy)
            proxies = Dict{String, String}()
            !isnothing(http_proxy) && (proxies["http"] = http_proxy)
            !isnothing(https_proxy) && (proxies["https"] = https_proxy)
        end
        
        new(payload, hookurl, proxies, http_timeout, verify, nothing)
    end
end

@inline function text(self::ConnectorCard, mtext::String)::ConnectorCard
    self.payload["text"] = mtext
    return self
end

@inline function title(self::ConnectorCard, mtitle::String)::ConnectorCard
    self.payload["title"] = mtitle
    return self
end

@inline function summary(self::ConnectorCard, msummary::String)::ConnectorCard
    self.payload["summary"] = msummary
    return self
end

function color(self::ConnectorCard, mcolor::String)::ConnectorCard
    # More efficient color handling with direct assignment
    self.payload["themeColor"] = if lowercase(mcolor) == "red"
        "E81123"
    elseif startswith(mcolor, "#")
        mcolor[2:end]  # Remove # prefix
    else
        mcolor
    end
    return self
end

function add_link_button(self::ConnectorCard, button_text::String, button_url::String)::ConnectorCard
    actions = get!(() -> Vector{Dict{String, Any}}(), self.payload, "potentialAction")
    
    push!(actions, Dict{String, Any}(
        "@context" => "http://schema.org",
        "@type" => "ViewAction",
        "name" => button_text,
        "target" => [button_url]
    ))
    
    return self
end

@inline function new_hook_url(self::ConnectorCard, nhookurl::String)::ConnectorCard
    isempty(nhookurl) && throw(ArgumentError("Webhook URL cannot be empty"))
    self.hookurl = nhookurl
    return self
end

function add_section(self::ConnectorCard, new_section::CardSection)::ConnectorCard
    sections = get!(() -> Vector{Dict{String, Any}}(), self.payload, "sections")
    push!(sections, dump_section(new_section))
    return self
end

function add_potential_action(self::ConnectorCard, new_action::PotentialAction)::ConnectorCard
    actions = get!(() -> Vector{Dict{String, Any}}(), self.payload, "potentialAction")
    push!(actions, dump_potential_action(new_action))
    return self
end

function print_me(self::ConnectorCard)
    println("Webhook URL: ", self.hookurl)
    println("Payload:")
    JSON3.pretty(self.payload)
end

"""
    send(card::ConnectorCard) -> Bool

Send the connector card to Microsoft Teams via webhook.
Returns true if successful, throws TeamsException on failure.
"""
function send(self::ConnectorCard)::Bool
    headers = ["Content-Type" => "application/json; charset=utf-8"]
    
    # Use JSON3.write for efficient serialization
    json_payload = JSON3.write(self.payload)
    
    try
        response = HTTP.post(
            self.hookurl, 
            headers, 
            json_payload;
            timeout=self.http_timeout,
            require_ssl_verification=self.verify,
            retry=false,  # Disable automatic retries for explicit control
            status_exception=true
        )
        
        self.last_http_response = response
        
        # Teams webhook returns 200 on success
        return 200 <= response.status < 300
        
    catch e
        if isa(e, HTTP.ExceptionRequest.StatusError)
            error_body = String(e.response.body)
            throw(TeamsException("HTTP $(e.status): $error_body"))
        elseif isa(e, HTTP.ConnectError)
            throw(TeamsException("Connection failed: Unable to reach webhook URL"))
        elseif isa(e, HTTP.TimeoutError)
            throw(TeamsException("Request timed out after $(self.http_timeout) seconds"))
        else
            throw(TeamsException("Unexpected error: $(sprint(showerror, e))"))
        end
    end
end

"""
    send_async(card::ConnectorCard) -> Task

Send the connector card asynchronously. Returns a Task that resolves to Bool.
"""
function send_async(self::ConnectorCard)::Task
    return @async send(self)
end

# ============================================================================
# Helper functions
# ============================================================================

"""
    format_url(display::String, url::String) -> String

Format a URL for markdown display in Teams messages.
"""
@inline format_url(display::String, url::String)::String = "[$display]($url)"

"""
    create_card(hookurl::String) -> ConnectorCard

Convenience constructor for creating a new ConnectorCard.
"""
@inline create_card(hookurl::String; kwargs...)::ConnectorCard = ConnectorCard(hookurl; kwargs...)

end # module Teams
