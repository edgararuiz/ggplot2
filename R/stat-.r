#' @section Stats:
#'
#' All `stat_*` functions (like `stat_bin`) return a layer that
#' contains a `Stat*` object (like `StatBin`). The `Stat*`
#' object is responsible for rendering the data in the plot.
#'
#' Each of the `Stat*` objects is a [ggproto()] object, descended
#' from the top-level `Stat`, and each implements various methods and
#' fields. To create a new type of Stat object, you typically will want to
#' implement one or more of the following:
#'
#' \itemize{
#'   \item Override one of :
#'     `compute_layer(self, data, scales, ...)`,
#'     `compute_panel(self, data, scales, ...)`, or
#'     `compute_group(self, data, scales, ...)`.
#'
#'     `compute_layer()` is called once per layer, `compute_panel_()`
#'     is called once per panel, and `compute_group()` is called once per
#'     group. All must return a data frame.
#'
#'     It's usually best to start by overriding `compute_group`: if
#'     you find substantial performance optimisations, override higher up.
#'     You'll need to read the source code of the default methods to see
#'     what else you should be doing.
#'
#'     `data` is a data frame containing the variables named according
#'     to the aesthetics that they're mapped to. `scales` is a list
#'     containing the `x` and `y` scales. There functions are called
#'     before the facets are trained, so they are global scales, not local
#'     to the individual panels.`...` contains the parameters returned by
#'     `setup_params()`.
#'   \item `finish_layer(data, params)`: called once for each layer. Used
#'     to modify the data after scales has been applied, but before the data is
#'     handed of to the geom for rendering. The default is to not modify the
#'     data. Use this hook if the stat needs access to the actual aesthetic
#'     values rather than the values that are mapped to the aesthetic.
#'   \item `setup_params(data, params)`: called once for each layer.
#'     Used to setup defaults that need to complete dataset, and to inform
#'     the user of important choices. Should return list of parameters.
#'   \item `setup_data(data, params)`: called once for each layer,
#'     after `setp_params()`. Should return modified `data`.
#'     Default methods removes all rows containing a missing value in
#'     required aesthetics (with a warning if `!na.rm`).
#'   \item `required_aes`: A character vector of aesthetics needed to
#'     render the geom.
#'   \item `default_aes`: A list (generated by [aes()] of
#'     default values for aesthetics.
#' }
#' @rdname ggplot2-ggproto
#' @format NULL
#' @usage NULL
#' @export
Stat <- ggproto("Stat",
  # Should the values produced by the statistic also be transformed
  # in the second pass when recently added statistics are trained to
  # the scales
  retransform = TRUE,

  default_aes = aes(),

  required_aes = character(),

  non_missing_aes = character(),

  setup_params = function(data, params) {
    params
  },

  setup_data = function(data, params) {
    data
  },

  compute_layer = function(self, data, params, layout) {
    check_required_aesthetics(
      self$required_aes,
      c(names(data), names(params)),
      snake_class(self)
    )

    data <- remove_missing(data, params$na.rm,
      c(self$required_aes, self$non_missing_aes),
      snake_class(self),
      finite = TRUE
    )

    # Trim off extra parameters
    params <- params[intersect(names(params), self$parameters())]

    args <- c(list(data = quote(data), scales = quote(scales)), params)
    plyr::ddply(data, "PANEL", function(data) {
      scales <- layout$get_scales(data$PANEL[1])
      tryCatch(do.call(self$compute_panel, args), error = function(e) {
        warning("Computation failed in `", snake_class(self), "()`:\n",
          e$message, call. = FALSE)
        data.frame()
      })
    })
  },

  compute_panel = function(self, data, scales, ...) {
    if (empty(data)) return(data.frame())

    groups <- split(data, data$group)
    stats <- lapply(groups, function(group) {
      self$compute_group(data = group, scales = scales, ...)
    })

    stats <- mapply(function(new, old) {
      if (empty(new)) return(data.frame())
      unique <- uniquecols(old)
      missing <- !(names(unique) %in% names(new))
      cbind(
        new,
        unique[rep(1, nrow(new)), missing,drop = FALSE]
      )
    }, stats, groups, SIMPLIFY = FALSE)

    do.call(plyr::rbind.fill, stats)
  },

  compute_group = function(self, data, scales) {
    stop("Not implemented", call. = FALSE)
  },

  finish_layer = function(self, data, params) {
    data
  },


  # See discussion at Geom$parameters()
  extra_params = "na.rm",
  parameters = function(self, extra = FALSE) {
    # Look first in compute_panel. If it contains ... then look in compute_group
    panel_args <- names(ggproto_formals(self$compute_panel))
    group_args <- names(ggproto_formals(self$compute_group))
    args <- if ("..." %in% panel_args) group_args else panel_args

    # Remove arguments of defaults
    args <- setdiff(args, names(ggproto_formals(Stat$compute_group)))

    if (extra) {
      args <- union(args, self$extra_params)
    }
    args
  },

  aesthetics = function(self) {
    c(union(self$required_aes, names(self$default_aes)), "group")
  }

)
