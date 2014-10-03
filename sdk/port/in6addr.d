module sdk.port.in6addr;

import sdk.port.base;

//
// IPv6 Internet address (RFC 2553)
// This is an 'on-wire' format structure.
//
struct in6_addr
{
    union _S6_union {
        UCHAR[16]      Byte;
        USHORT[8]      Word;

	alias Byte _S6_u8;
    };
    alias _S6_union u;
    
    //
    // Defines to match RFC 2553.
    //
    alias u _S6_un;
    alias u.Byte s6_addr;

    //
    // Defines for our implementation.
    //
    alias u.Byte  s6_bytes;
    alias u.Word  s6_words;
}

alias in6_addr IN6_ADDR;
alias in6_addr* PIN6_ADDR;
alias in6_addr* /*FAR*/ *LPIN6_ADDR;

alias in6_addr in_addr6;

