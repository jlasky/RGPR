
#' @name convertTimeToDepth
#' @rdname convertTimeToDepth
#' @export
setGeneric("convertTimeToDepth", function(x, dz = NULL, dmax = NULL, ...) 
  standardGeneric("convertTimeToDepth"))


# max_depth = to which depth should the migration be performed
# dz = vertical resolution of the migrated data
# fdo = dominant frequency of the GPR signal

# for static time-to-depth migration 
# dz = depth resolution for the time to depth conversion. If dz = NULL, then
#      dz is set equal to the smallest depth resolution computed from x_depth.
# d_max = maximum depth for the time to depth conversion. If d_max = NULL, then
#         d_max is set equal to the largest depth in x_depth.
# method = method for the interpolation (see ?signal::interp1)

#' Migrate of the GPR data
#' 
#' Fresnel zone defined according to 
#' Perez-Gracia et al. (2008) Horizontal resolution in a non-destructive
#' shallow GPR survey: An experimental evaluation. NDT & E International,
#' 41(8): 611-620.
#' doi:10.1016/j.ndteint.2008.06.002
#'
#' @param max_depth maximum depth to appply the migration
#' @param dz        vertical resolution of the migrated data
#' @param fdo       dominant frequency of the GPR signal
#' 
#' @name convertTimeToDepth
#' @rdname convertTimeToDepth
#' @export
setMethod("convertTimeToDepth", "GPR", function(x, type = c("static", "kirchhoff"), ...){
  if(is.null(x@vel) || length(x@vel)==0){
    stop("You must first define the EM wave velocity ",
         "with 'vel(x) <- 0.1' for example!")
  }
  if(length(x@coord) != 0 && ncol(x@coord) == 3){
    topo <- x@coord[1:ncol(x@data), 3]
  }else{
    topo <- rep.int(0L, ncol(x@data))
    message("Trace vertical positions set to zero!")
  }
  
  if(any(x@time0 != 0)){
    x <- time0Cor(x, method = c("pchip"))
  }
  
  if( !isTimeUnit(x) ){
    stop("Vertical unit (", x@depthunit , ") is not a time unit...")
  }
    
  dots <- list(...)
    
    
  # single velocity value
  if(length(x@vel[[1]]) == 1){
    message("time to depth conversion with constant velocity (", x@vel[[1]],
            " ", x@posunit, "/", x@depthunit, ")")
    z <- timeToDepth(x@depth, time_0 = 0, v = vel(x), 
                     antsep = antsep(x))
    x <- x[!is.na(z),]
    x@dz <-  x@dz * x@vel[[1]]/ 2
    x@depth <- seq(from = 0, to = tail(z, 1), by = x@dz)
    funInterp <- function(x, z, zreg){
      signal::interp1(x = z, y = x, xi = zreg, 
                      method = "pchip", extrap = TRUE)
    }
    x@data <- apply(x@data, 2, funInterp, 
                    z = z[!is.na(z)], zreg = x@depth)
  # vector velocity
  }else if( is.null(dim(x@vel[[1]])) && length(x@vel[[1]]) == nrow(x) ){
    x_depth <- timeToDepth(x@depth, 0, v = x@vel[[1]], 
                           antsep = x@antsep) # here difference to matrix case
    test <- !is.na(x_depth)
    x <- x[test,]
    x_depth <- x_depth[test]
    if( !is.null(dots$dz)){
      dz <- dots$dz
    }else{
      dz <- min(x@vel[[1]]) * min(diff(depth(x)))/2
    }
    if( !is.null(dots$dmax)){
      dmax <- dots$dmax
    }else{
      dmax <- max(x_depth, na.rm = TRUE)
    }
    print(dmax)
    if( !is.null(dots$method)){
      method <- match.arg(dots$method, c("linear", "nearest", "pchip", "cubic", "spline"))
    }else{
      method <- "pchip"
    }
    
    d <- seq(from = 0, by = dz, to = dmax)
    funInterp <- function(A, x_depth, x_depth_int, method){
      signal::interp1(x = x_depth, y = A, xi = x_depth_int, 
                      method = method)
    }
    x@data <- apply(x@data, 2, funInterp, 
                    x_depth = x_depth, 
                    x_depth_int = d, 
                    method = method)
    
    # x_new <- matrix(nrow = length(d), ncol = ncol(x))
    # for(i in seq_along(x)){
    #   x_new[, i] <- signal::interp1(x  = x_depth,  # here difference to matrix case
    #                                 y  = as.numeric(x[,i]),
    #                                 xi = d,
    #                                 method = method)
    # }
    # x@data      <- x_new
    x@depth     <- d
    x@dz        <- dz
      
    print("lkj")
  # matrix velocity
  }else if(is.matrix(x@vel[[1]])){
    x_depth <- apply(c(0, diff(depth(x))) * x@vel[[1]]/2, 2, cumsum)
    # FIXME account for antenna separation -> and remove pixels with NA... not so easy..
    # x_depth <- apply(c(0, diff(depth(x))) * x@vel[[1]]/2, 2, cumsum)
    # x_detph <- x_depth^2 - antsep^2
    # test <- (x_detph >= 0)
    # x_detph[!test] <- NA
    # x_detph[test] <- sqrt(x_detph[test])/2
    if( !is.null(dots$dz)){
      dz <- dots$dz
    }else{
      dz <- min(x@vel[[1]]) * min(diff(depth(x)))/2
    }
    if( !is.null(dots$dmax)){
      dmax <- dots$dmax
    }else{
      dmax <- max(x_depth)
    }
    if( !is.null(dots$method)){
      method <- match.arg(dots$method, c("linear", "nearest", "pchip", "cubic", "spline"))
    }else{
      method <- "pchip"
    }
    d <- seq(from = 0, by = dz, to = dmax)
    x_new <- matrix(nrow = length(d), ncol = ncol(x))
    for(i in seq_along(x)){
      x_new[, i] <- signal::interp1(x  = as.numeric(x_depth[,i]),
                                    y  = as.numeric(x[,i]),
                                    xi = d,
                                    method = method)
    }
    x@data      <- x_new
    x@depth     <- d
    x@dz        <- dz
  }
  x@depthunit <- "m"
  
  zShift <- (max(topo) - topo)
  if( all(zShift != 0) ){
    x <- traceShift(x,  ts = zShift, method = c("pchip"), crop = FALSE)
  }
  if(length(x@coord) > 0 && ncol(x@coord) == 3 ){
    x@coord[, 3] <- max(x@coord[,3])
  }
  x@vel <- list() 

  proc(x) <- getArgs()
  return(x)
} 
)

