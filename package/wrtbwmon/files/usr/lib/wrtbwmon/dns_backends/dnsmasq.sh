#!/bin/sh
# DNS Backend: dnsmasq
# Parses dnsmasq logs for DNS queries and responses

# Parse dnsmasq log for DNS A/AAAA records
# Returns: Writes to QUERIES_FILE and MAPPINGS_FILE
dns_backend_dnsmasq_parse() {
    local queries_file="$1"
    local mappings_file="$2"
    local current_timestamp=$(date +%s)

    # Clear output files
    > "$queries_file"
    > "$mappings_file"

    # Get last 500 dnsmasq logs
    local log_file
    log_file=$(create_temp_file "dnsmasq_recent")
    logread | grep "dnsmasq\[" | tail -5000 > "$log_file"

    # Process queries
    while IFS= read -r line; do
        # Process A records (IPv4)
        if echo "$line" | grep -q "query\[A\]"; then
            local domain
            local client_ip
            domain=$(echo "$line" | sed -n 's/.*query\[A\] \([^ ]*\) from.*/\1/p')
            client_ip=$(echo "$line" | sed -n 's/.*from \([0-9.]*\).*/\1/p')

            if [ -n "$domain" ] && [ -n "$client_ip" ]; then
                local mac
                mac=$(ip neigh show "$client_ip" 2>/dev/null | awk '{print $5}' | head -1)

                if [ -n "$mac" ] && [ "$mac" != "FAILED" ]; then
                    echo "$client_ip|$mac|$domain|$current_timestamp" >> "$queries_file"
                fi
            fi
        fi

        # Process AAAA records (IPv6)
        if echo "$line" | grep -q "query\[AAAA\]"; then
            local domain
            local client_ip
            domain=$(echo "$line" | sed -n 's/.*query\[AAAA\] \([^ ]*\) from.*/\1/p')
            client_ip=$(echo "$line" | sed -n 's/.*from \([0-9a-f:]*\).*/\1/p')

            if [ -n "$domain" ] && [ -n "$client_ip" ]; then
                local mac
                mac=$(ip neigh show "$client_ip" 2>/dev/null | awk '{print $5}' | head -1)

                if [ -n "$mac" ] && [ "$mac" != "FAILED" ]; then
                    echo "$client_ip|$mac|$domain|$current_timestamp" >> "$queries_file"
                fi
            fi
        fi
    done < "$log_file"

    # Process replies
    while IFS= read -r line; do
        # Process IPv6 replies first (more specific pattern with colons)
        if echo "$line" | grep -q "reply.*is [0-9a-f]*:[0-9a-f:]"; then
            local domain
            local resolved_ip
            domain=$(echo "$line" | sed -n 's/.*reply \([^ ]*\) is.*/\1/p')
            resolved_ip=$(echo "$line" | sed -n 's/.*is \([0-9a-f:]*\).*/\1/p')

            if [ -n "$domain" ] && [ -n "$resolved_ip" ] && [ "$resolved_ip" != "::" ]; then
                echo "$resolved_ip|$domain|$current_timestamp" >> "$mappings_file"
            fi
        # Process IPv4 replies (dotted decimal, no colons)
        elif echo "$line" | grep -q "reply.*is [0-9][0-9.]*$"; then
            local domain
            local resolved_ip
            domain=$(echo "$line" | sed -n 's/.*reply \([^ ]*\) is.*/\1/p')
            resolved_ip=$(echo "$line" | sed -n 's/.*is \([0-9.]*\).*/\1/p')

            if [ -n "$domain" ] && [ -n "$resolved_ip" ] && [ "$resolved_ip" != "0.0.0.0" ]; then
                echo "$resolved_ip|$domain|$current_timestamp" >> "$mappings_file"
            fi
        fi
    done < "$log_file"

    rm -f "$log_file"
}

# Check if dnsmasq backend is available
dns_backend_dnsmasq_available() {
    command -v logread >/dev/null 2>&1 && \
    logread | grep -q "dnsmasq\["
}
