#' Parse and build URLs
#'
#' `url_parse()` parses a URL into its component pieces; `url_build()` does
#' the reverse, converting a list of pieces into a string URL. See
#' [rfc3986](https://www.rfc-editor.org/rfc/rfc3986) for details of parsing
#' algorithm.
#'
#' @param url For `url_parse()` a string to parse into a URL;
#'   for `url_build()` a URL to turn back into a string.
#' @returns
#' * `url_build()` returns a string.
#' * `url_parse()` returns a URL: a S3 list with class `httr2_url`
#'   and elements `scheme`, `hostname`, `port`, `path`, `fragment`, `query`,
#'   `username`, `password`.
#' @export
#' @examples
#' url_parse("http://google.com/")
#' url_parse("http://google.com:80/")
#' url_parse("http://google.com:80/?a=1&b=2")
#' url_parse("http://username@google.com:80/path;test?a=1&b=2#40")
#'
#' url <- url_parse("http://google.com/")
#' url$port <- 80
#' url$hostname <- "example.com"
#' url$query <- list(a = 1, b = 2, c = 3)
#' url_build(url)
url_parse <- function(url) {
  check_string(url, "`url`")

  # https://datatracker.ietf.org/doc/html/rfc3986#appendix-B
  pieces <- parse_match(url, "^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?")

  scheme <- pieces[[2]]
  authority <- pieces[[4]]
  path <- pieces[[5]]
  query <- pieces[[7]]
  if (!is.null(query)) {
    query <- query_parse(query)
  }
  fragment <- pieces[[9]]

  # https://datatracker.ietf.org/doc/html/rfc3986#section-3.2
  pieces <- parse_match(authority %||% "", "^(([^@]+)@)?([^:]+)?(:([^#]+))?")

  userinfo <- pieces[[2]]
  if (!is.null(userinfo)) {
    if (grepl(":", userinfo)) {
      userinfo <- parse_in_half(userinfo, ":")
    } else {
      userinfo <- list(userinfo, NULL)
    }
  }
  hostname <- pieces[[3]]
  port <- pieces[[5]]

  structure(
    list(
      scheme = scheme,
      hostname = hostname,
      username = userinfo[[1]],
      password = userinfo[[2]],
      port = port,
      path = path,
      query = query,
      fragment = fragment
    ),
    class = "httr2_url"
  )
}

url_modify <- function(url, ...) {
  url <- url_parse(url)
  url <- modify_list(url, ...)
  url_build(url)
}

is_url <- function(x) inherits(x, "httr2_url")

#' @export
print.httr2_url <- function(x, ...) {
  cli::cli_text("{.cls {class(x)}} {url_build(x)}")
  if (!is.null(x$scheme)) {
    cli::cli_li("{.field scheme}: {x$scheme}")
  }
  if (!is.null(x$hostname)) {
    cli::cli_li("{.field hostname}: {x$hostname}")
  }
  if (!is.null(x$username)) {
    cli::cli_li("{.field username}: {x$username}")
  }
  if (!is.null(x$password)) {
    cli::cli_li("{.field password}: {x$password}")
  }
  if (!is.null(x$port)) {
    cli::cli_li("{.field port}: {x$port}")
  }
  if (!is.null(x$path)) {
    cli::cli_li("{.field path}: {x$path}")
  }
  if (!is.null(x$query)) {
    cli::cli_li("{.field query}: ")
    id <- cli::cli_ul()
    # escape curly brackets for cli by replacing single with double brackets
    query_vals <- gsub("\\{", "{{", gsub("\\}", "}}", x$query))
    cli::cli_li(paste0("  {.field ", names(x$query), "}: ", query_vals))
    cli::cli_end(id)
  }
  if (!is.null(x$fragment)) {
    cli::cli_li("{.field fragment}: {x$fragment}")
  }
  invisible(x)
}

#' @export
#' @rdname url_parse
url_build <- function(url) {
  if (!is.null(url$query)) {
    query <- query_build(url$query)
  } else {
    query <- NULL
  }

  if (is.null(url$username) && is.null(url$password)) {
    user_pass <- NULL
  } else if (is.null(url$username) && !is.null(url$password)) {
    abort("Cannot set url password without username")
  } else if (!is.null(url$username) && is.null(url$password)) {
    user_pass <- paste0(url$username, "@")
  } else {
    user_pass <- paste0(url$username, ":", url$password, "@")
  }

  if (!is.null(user_pass) || !is.null(url$hostname) || !is.null(url$port)) {
    authority <- paste0(user_pass, url$hostname)
    if (!is.null(url$port)) {
      authority <- paste0(authority, ":", url$port)
    }
  } else {
    authority <- NULL
  }

  prefix <- function(prefix, x) if (!is.null(x)) paste0(prefix, x)
  paste0(
    url$scheme, if (!is.null(url$scheme)) ":",
    if (!is.null(url$scheme) || !is.null(authority)) "//",
    authority, url$path,
    prefix("?", query),
    prefix("#", url$fragment)
  )
}

query_parse <- function(x) {
  x <- gsub("^\\?", "", x) # strip leading ?, if present
  params <- parse_name_equals_value(parse_delim(x, "&"))

  if (length(params) == 0) {
    return(NULL)
  }

  out <- as.list(curl::curl_unescape(params))
  names(out) <- curl::curl_unescape(names(params))
  out
}

query_build <- function(x) {
  if (!is_list(x) || (!is_named(x) && length(x) > 0)) {
    abort("Query must be a named list")
  }

  x <- compact(x)
  if (length(x) == 0) {
    return(NULL)
  }

  bad_val <- lengths(x) != 1 | !map_lgl(x, is_atomic)
  if (any(bad_val)) {
    abort(c(
      "Query parameters must be length 1 atomic vectors.",
      paste0("Problems: ", paste0(names(x)[bad_val], collapse =", "))
    ))
  }

  is_double <- map_lgl(x, is.double)
  x[is_double] <- map_chr(x[is_double], format, scientific = FALSE)

  names <- curl::curl_escape(names(x))
  values <- map_chr(x, url_escape)

  paste0(names, "=", values, collapse = "&")
}

url_escape <- function(x) {
  if (inherits(x, "AsIs")) {
    x
  } else {
    curl::curl_escape(x)
  }
}
